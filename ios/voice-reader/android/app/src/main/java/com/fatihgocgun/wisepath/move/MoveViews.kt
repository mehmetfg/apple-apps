// Yolda's always-visible pieces (port of MoveViews.swift and MarkHold.swift): the mode's icon that moves while you
// move (the bicycle's wheels turn with the speed, the walker steps), the mode menu, the quiet top line (clock ·
// battery · speed; the way's numbers large on a tap), the book switch, the body-weight question and the mark key's
// hold (a held mark grows back a sentence every 0.6 s).
package com.fatihgocgun.wisepath.move

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Battery2Bar
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.settings.BikeLook
import com.fatihgocgun.wisepath.settings.MoveKind
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.cos
import kotlin.math.sin

// MARK: - the icon that moves

/** The bicycle with turning wheels (faster with the speed, still when stopped), or the walking figure stepping. */
@Composable
fun MoveIcon(kind: MoveKind, speed: Double, size: Dp = 30.dp, color: Color) {
    var t by remember { mutableLongStateOf(0L) }
    val moving = speed >= 1
    LaunchedEffect(moving) { if (moving) while (isActive) withFrameMillis { t = it } }
    if (kind == MoveKind.bike) {
        // a 70 cm wheel at this speed, slowed to a quarter so the eye can follow it
        val revs = speed / 3.6 / (0.7 * Math.PI) / 4
        val angle = (t % 3_600_000L) / 1000.0 * revs * 2 * Math.PI
        Canvas(Modifier.size(size * 1.45f, size)) {
            val w = this.size.width; val h = this.size.height
            val rad = h * 0.3f
            val back = Offset(rad + 1, h - rad - 1)
            val front = Offset(w - rad - 1, back.y)
            val p = Path()
            for (c in listOf(back, front)) {
                p.addOval(androidx.compose.ui.geometry.Rect(c, rad))
                for (k in 0 until 3) {
                    val a = angle + k * Math.PI / 3
                    val dx = (cos(a) * rad * 0.82).toFloat(); val dy = (sin(a) * rad * 0.82).toFloat()
                    p.moveTo(c.x - dx, c.y - dy); p.lineTo(c.x + dx, c.y + dy)
                }
            }
            val pedal = Offset(w * 0.47f, back.y)
            val seat = Offset(w * 0.38f, h * 0.26f)
            val head = Offset(w * 0.70f, h * 0.24f)
            p.moveTo(back.x, back.y); p.lineTo(pedal.x, pedal.y); p.lineTo(seat.x, seat.y); p.lineTo(back.x, back.y)
            p.moveTo(pedal.x, pedal.y); p.lineTo(head.x, head.y); p.lineTo(front.x, front.y)
            p.moveTo(seat.x, seat.y); p.lineTo(head.x - w * 0.02f, head.y + h * 0.02f)
            p.moveTo(seat.x - w * 0.07f, seat.y - h * 0.06f); p.lineTo(seat.x + w * 0.05f, seat.y - h * 0.06f)
            p.moveTo(head.x, head.y); p.lineTo(head.x + w * 0.04f, head.y - h * 0.12f)
            drawPath(p, color, style = Stroke(width = maxOf(1.6.dp.toPx(), size.toPx() / 14), cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
    } else {
        // the walker bobs with the step, quicker with the speed
        val bob = if (moving) sin(t / 1000.0 * Math.PI * 2 * (speed / 4).coerceIn(0.6, 2.0)).toFloat() else 0f
        Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null, tint = color,
            modifier = Modifier.size(size).graphicsLayer { translationY = -kotlin.math.abs(bob) * 3.dp.toPx() })
    }
}

/**
 * The icon as the mode's button: the view (Yolda · Kinetik · Tam metin · Klasik), the light, switch between bicycle
 * and walking, Müzik modu, or leave the mode (only that ends the GPS record).
 */
@Composable
fun MoveModeMenu(app: AppModel, color: Color, size: Dp = 24.dp, onOpenReader: () -> Unit, onMusic: () -> Unit, onExit: () -> Unit) {
    val s = app.settings
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    Box(Modifier.widthIn(min = 44.dp).height(40.dp).clickable { open = true }, contentAlignment = Alignment.Center) {
        MoveIcon(s.moveKind, Workouts.speed, size, color)
        DropdownMenu(open, onDismissRequest = { open = false }) {
            MenuHeader("Görünüm")
            BikeLook.entries.forEach { look ->
                CheckItem(look.label, s.bikeLook == look) {
                    open = false
                    s.bikeLook = look
                    if (look == BikeLook.full) onOpenReader()
                }
            }
            if (s.bikeLook == BikeLook.kinetic) {
                MenuHeader("Kinetik yazı")
                CheckItem("Vuruş", !s.kineticMask) { s.kineticMask = false; open = false }
                CheckItem("Perde", s.kineticMask) { s.kineticMask = true; open = false }
            }
            MenuHeader("Işık")
            RideLight.entries.forEach { l -> CheckItem(l.label, s.rideLight == l.name) { s.rideLight = l.name; open = false } }
            HorizontalDivider()
            val other = if (s.moveKind == MoveKind.bike) MoveKind.walk else MoveKind.bike
            DropdownMenuItem(text = { Text(if (other == MoveKind.walk) "Yürüyüşe geç" else "Bisiklete geç") }, onClick = {
                open = false
                s.moveKind = other
                WorkoutService.start(context)
            })
            DropdownMenuItem(text = { Text("Müzik modu") }, onClick = { open = false; onMusic() })
            DropdownMenuItem(text = { Text("${s.moveKind.label} modundan çık (GPS durur)", color = Color(0xFFE5484D)) },
                onClick = { open = false; onExit() })
        }
    }
}

@Composable
private fun MenuHeader(text: String) {
    Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.Gray, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

@Composable
private fun CheckItem(text: String, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(text) }, onClick = onClick,
        leadingIcon = { if (checked) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) })
}

// MARK: - the quiet line at the top

private data class Battery(val percent: Int?, val charging: Boolean)

private fun battery(context: Context): Battery {
    val i = runCatching { context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) }.getOrNull()
        ?: return Battery(null, false)
    val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
    val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
    val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
    return Battery(if (level >= 0 && scale > 0) Math.round(level * 100f / scale) else null,
        st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL)
}

private val clockFormat = DateTimeFormatter.ofPattern("HH:mm")

/**
 * The road screen's and the music mode's quiet top: the clock and the battery on one line, the speed (in a moving
 * mode) and a label in small faint capitals under it, and, where asked, the book. Asks for the body weight once,
 * when a moving mode first shows it.
 */
@Composable
fun RoadStatus(app: AppModel, modifier: Modifier = Modifier, label: String? = null, book: String? = null, ink: Color, dim: Color) {
    val context = LocalContext.current
    var tick by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) { while (true) { tick = System.currentTimeMillis(); delay(5000) } }
    val bat = remember(tick) { battery(context) }
    val time = remember(tick) { LocalTime.now().format(clockFormat) }
    var askWeight by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val p = context.getSharedPreferences("wisepath.move", Context.MODE_PRIVATE)
        if (app.settings.bikeMode && app.settings.bodyWeight == 0.0 && !p.getBoolean("v.weightAsked", false)) {
            p.edit().putBoolean("v.weightAsked", true).apply()
            askWeight = true
        }
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(time, fontFamily = RideColors.mono, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = ink)
            Text("·", fontFamily = RideColors.mono, fontSize = 12.sp, color = ink)
            val pct = bat.percent ?: 100
            val bc = if (pct < 10) Color.Red else if (pct < 20) Color(0xFFFF9500) else ink
            Icon(if (bat.charging) Icons.Filled.BatteryChargingFull else if (pct < 20) Icons.Filled.Battery2Bar else Icons.Filled.BatteryFull,
                null, tint = bc, modifier = Modifier.size(14.dp))
            Text(bat.percent?.let { "%$it" } ?: "–", fontFamily = RideColors.mono, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = bc)
        }
        val speed = if (app.settings.bikeMode) "${Math.round(Workouts.speed)} km/sa" else null
        val second = listOfNotNull(label, speed)
        if (second.isNotEmpty()) Text(second.joinToString(" · ").uppercase(RideTr), fontFamily = RideColors.mono, fontSize = 11.sp,
            fontWeight = FontWeight.Medium, letterSpacing = 1.6.sp, color = dim, maxLines = 1)
        if (book != null) Text(book, fontSize = 11.sp, color = dim, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    if (askWeight) WeightDialog(app, long = true) { askWeight = false }
}

val RideTr = java.util.Locale("tr", "TR")

@Composable
fun WeightDialog(app: AppModel, long: Boolean, onDone: () -> Unit) {
    var text by remember { mutableStateOf(if (app.settings.bodyWeight > 0) "${app.settings.bodyWeight.toInt()}" else "") }
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text("Kalori için kilon") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(if (long) "Kalori kilona, hızına ve eğime göre hesaplanır. Girmezsen 75 kg sayılır; üst satıra dokununca açılan göstergede kaloriye dokunarak sonra da girebilirsin."
                     else "Kalori kilona, hızına ve eğime göre hesaplanır. Girmezsen 75 kg sayılır.")
                OutlinedTextField(text, { text = it }, label = { Text("kg") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            }
        },
        confirmButton = {
            TextButton(onClick = {
                text.replace(',', '.').toDoubleOrNull()?.let { if (it > 30 && it < 250) app.settings.bodyWeight = it }
                onDone()
            }) { Text("Kaydet") }
        },
        dismissButton = { TextButton(onClick = onDone) { Text("Sonra") } },
    )
}

// MARK: - the way's numbers

object MoveStrip {
    fun km(m: Double): String = String.format(RideTr, if (m < 10_000) "%.2f" else "%.1f", m / 1000)
    fun clock(s: Double): String {
        val t = s.toInt().coerceAtLeast(0); val h = t / 3600; val m = (t % 3600) / 60; val sec = t % 60
        return if (h > 0) "$h:%02d".format(m) else "$m:%02d".format(sec)
    }
}

/**
 * The way's numbers large in the middle of the screen, gone by themselves after six seconds (a tap hides them
 * sooner): time, km, calories, speed (steps on foot), average and climb.
 */
@Composable
fun MoveBoard(app: AppModel, shown: MutableState<Boolean>) {
    val r = LocalRide.current
    var askWeight by remember { mutableStateOf(false) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(shown.value, askWeight) {
        if (!shown.value) return@LaunchedEffect
        val until = System.currentTimeMillis() + 6000
        while (System.currentTimeMillis() < until || askWeight) { now = System.currentTimeMillis(); delay(1000) }
        shown.value = false
    }
    AnimatedVisibility(shown.value, enter = fadeIn() + scaleIn(initialScale = 0.92f), exit = fadeOut()) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
            .clickable(remember { MutableInteractionSource() }, null) { shown.value = false }, contentAlignment = Alignment.Center) {
            val w = Workouts.current
            val walk = app.settings.moveKind == MoveKind.walk
            Column(
                Modifier.padding(horizontal = 20.dp).background(r.panel, RoundedCornerShape(26.dp))
                    .border(1.dp, r.line, RoundedCornerShape(26.dp)).padding(26.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Text(app.settings.moveKind.label.uppercase(RideTr), fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = r.amber)
                Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                    Big(MoveStrip.clock(w?.let { (now - it.start) / 1000.0 } ?: 0.0), "süre")
                    Big(MoveStrip.km(w?.distance ?: 0.0), "km")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                    Box(Modifier.clickable { askWeight = true }) {
                        Big("${Math.round(w?.calories ?: 0.0)}", if (app.settings.bodyWeight > 0) "kcal" else "kcal · kilo ?")
                    }
                    if (walk) Big("${w?.steps ?: 0}", "adım") else Big("${Math.round(Workouts.speed)}", "km/sa")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                    Big(String.format(RideTr, "%.1f", w?.averageSpeed ?: 0.0), "ort. km/sa", small = true)
                    Big("${Math.round(w?.climb ?: 0.0)}", "m tırmanış", small = true)
                }
                if (Workouts.status.isNotEmpty()) Text(Workouts.status, fontSize = 12.sp, color = r.muted)
            }
        }
    }
    if (askWeight) WeightDialog(app, long = false) { askWeight = false }
}

@Composable
private fun Big(value: String, unit: String, small: Boolean = false) {
    val r = LocalRide.current
    Column(Modifier.widthIn(min = 110.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, fontSize = if (small) 30.sp else 46.sp, fontWeight = FontWeight.Bold, color = r.paper, maxLines = 1)
        Text(unit, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = r.muted)
    }
}

/** Km · time · calories, and steps on foot or speed on the bicycle, and the climb (the Klasik page's strip). */
@Composable
fun MoveStripRow(app: AppModel, ink: Color, dim: Color) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    val w = Workouts.current
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        @Composable fun cell(v: String, u: String) = Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(v, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = ink, maxLines = 1)
            Text(u, fontSize = 10.sp, fontWeight = FontWeight.Medium, color = dim, maxLines = 1)
        }
        cell(MoveStrip.km(w?.distance ?: 0.0), "km")
        cell(MoveStrip.clock(w?.let { (now - it.start) / 1000.0 } ?: 0.0), "süre")
        cell("${Math.round(w?.calories ?: 0.0)}", "kcal")
        if (app.settings.moveKind == MoveKind.walk) cell("${w?.steps ?: 0}", "adım") else cell("${Math.round(Workouts.speed)}", "km/sa")
        if (w != null && w.climb >= 1) cell("${Math.round(w.climb)}", "m ↑")
    }
}

// MARK: - switching the book

/** A long press on the library key: the books in progress (the last opened first), without leaving the moving mode. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookSwitchSheet(app: AppModel, onDismiss: () -> Unit) {
    val r = LocalRide.current
    val docs by app.store.documents.collectAsState()
    val scope = rememberCoroutineScope()
    val recent = docs.filter { it.id != app.player.documentID && it.lastOpenedAt != null && !it.isFinished }
        .sortedByDescending { it.lastOpenedAt }.take(8)
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = r.panel, contentColor = r.paper) {
        Text("Başka kitaba geç", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        if (recent.isEmpty()) Text("Süren başka kitap yok", color = r.muted, modifier = Modifier.padding(20.dp))
        LazyColumn(Modifier.padding(bottom = 24.dp)) {
            items(recent, key = { it.id }) { d ->
                Row(Modifier.fillMaxWidth().clickable {
                    onDismiss()
                    scope.launch { app.open(d.id); app.player.play() }
                }.padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.Book, null, tint = r.amber)
                    Column {
                        Text(d.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text("%${(d.progress * 100).toInt()}", fontSize = 12.sp, color = r.muted)
                    }
                }
            }
        }
    }
}

// MARK: - the mark key's hold

/**
 * A tap marks (or unmarks) the sentence being heard; held, the sentence is marked after 0.45 s and the mark grows back
 * one sentence every 0.6 s while the finger stays (`count` shows how many sentences it holds; 0 when not holding).
 */
@Composable
fun Modifier.markHold(app: AppModel, mark: () -> Unit, count: MutableState<Int>): Modifier {
    val scope = rememberCoroutineScope()
    val doMark by rememberUpdatedState(mark)
    return this.pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown()
            var long = false
            val job = scope.launch {
                delay(450)
                long = true
                if (!app.spokenSentenceMarked()) doMark()
                count.value = app.markChain?.count ?: 1
                while (isActive) {
                    delay(600)
                    val n = app.extendMarkBack() ?: break
                    count.value = n
                }
            }
            val up = waitForUpOrCancellation()
            job.cancel()
            if (!long) { if (up != null) doMark() }
            else scope.launch { delay(1200); count.value = 0 }
        }
    }
}

/**
 * Hold half a second to start a voice note (`progress` runs 0 → 1 while holding, for a ring round the key), tap to
 * end it: a stray touch never starts a recording.
 */
@Composable
fun Modifier.micHold(app: AppModel, progress: MutableState<Float>, onStart: () -> Unit, onStop: () -> Unit): Modifier {
    val scope = rememberCoroutineScope()
    val start by rememberUpdatedState(onStart)
    val stop by rememberUpdatedState(onStop)
    return this.pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown()
            if (app.recording) {
                if (waitForUpOrCancellation() != null) { app.finishVoiceNote(); stop() }
                return@awaitEachGesture
            }
            val job = scope.launch {
                val t0 = System.currentTimeMillis()
                while (isActive) {
                    val p = (System.currentTimeMillis() - t0) / 500f
                    progress.value = p.coerceAtMost(1f)
                    if (p >= 1f) { app.startVoiceNote(); start(); break }
                    delay(16)
                }
            }
            waitForUpOrCancellation()
            job.cancel()
            progress.value = 0f
        }
    }
}
