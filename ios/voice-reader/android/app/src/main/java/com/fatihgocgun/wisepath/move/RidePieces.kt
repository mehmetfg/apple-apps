// The road screen's pieces that follow the voice (port of RideView.swift): the page of the last sentences heard
// (RestLayer), the rest bar that moves the reading place, the book line, the whole book's progress, the dock (speed ·
// voice note · mark), the mark's burst, the warm tint, and the contents with a look at another place.
package com.fatihgocgun.wisepath.move

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.FormatClear
import androidx.compose.material.icons.filled.LinearScale
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.settings.NavigationUnit
import kotlinx.coroutines.Job
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.sin

// MARK: - the screen's state

class RideState(private val scope: CoroutineScope) {
    val sediment = mutableStateListOf<String>()
    var leaves by mutableIntStateOf(0)
    var falling by mutableIntStateOf(0)
    var toast by mutableStateOf<String?>(null)
    var concepts: Map<Int, String> = emptyMap()
    var markPoint = Offset.Zero
    private var toastJob: Job? = null

    /** The voice reached a word: its concept joins the sediment. */
    fun heard(word: IntRange?) {
        val label = word?.let { concepts[it.first] } ?: return
        if (label in sediment) return
        sediment.add(label)
        if (sediment.size > 24) sediment.removeAt(0)
    }

    fun marked(added: Boolean) {
        if (added) { leaves++; falling++ } else leaves = maxOf(0, leaves - 1)
        say(if (added) "Cümle işaretlendi" else "İşaret kaldırıldı")
    }

    fun say(text: String) {
        toast = text
        toastJob?.cancel()
        toastJob = scope.launch { delay(1800); toast = null }
    }

    fun reset() { sediment.clear(); leaves = 0 }
}

// MARK: - the warm tint

/** A warm glow whose hue drifts with the sentences, slowly enough not to be noticed. */
@Composable
fun RideTint(app: AppModel) {
    val r = LocalRide.current
    val spoken by app.player.spoken.collectAsState()
    val st by app.player.state.collectAsState()
    val at = spoken.sentence?.first ?: st.cursor
    val hue by animateFloatAsState(24f + ((at / 600) % 9) * 7f, tween(6000, easing = LinearEasing), label = "hue")
    val c = if (r.day) Color.hsv(hue, 0.35f, 1f).copy(alpha = 0.22f) else Color.hsv(hue, 0.45f, 0.14f).copy(alpha = 0.55f)
    Canvas(Modifier.fillMaxSize()) {
        drawRect(Brush.radialGradient(listOf(c, Color.Transparent), Offset(size.width / 2, size.height * 0.32f), size.width * 0.9f))
    }
}

// MARK: - the page of the last sentences

private class Piece(val range: IntRange, val shownEnd: Int, val past: Boolean)

/**
 * The sentences heard since the page began, the one being heard up to the word being heard (what comes next is never
 * shown, so the eye does not run ahead of the voice). When the page is full it turns: the heard sentence starts the
 * next page at the top. The older a sentence on the page, the fainter; a marked one has a gold wash and a bar.
 */
@Composable
fun RestLayer(app: AppModel, w: Dp, concepts: Map<Int, String>, markTick: Int, modifier: Modifier = Modifier) {
    val r = LocalRide.current
    val st by app.player.state.collectAsState()
    val spoken by app.player.spoken.collectAsState()
    app.store.documents.collectAsState().value
    val nav = app.player.nav
    val cur = spoken.sentence ?: nav.sentenceRange(st.cursor)
    var pageStart by remember { mutableIntStateOf(-1) }
    val density = LocalDensity.current
    val fontSize = with(density) { (w * 0.058f).toSp() }
    val bigSize = with(density) { (w * 0.062f).toSp() }
    val pastBig = with(density) { (w * 0.05f).toSp() }
    val gap = w * 0.035f
    val measurer = rememberTextMeasurer()
    val sweep = remember { Animatable(-0.4f) }
    LaunchedEffect(markTick) { if (markTick > 0) { sweep.snapTo(-0.4f); sweep.animateTo(1.1f, tween(900, easing = FastOutSlowInEasing)) } }

    BoxWithConstraints(modifier) {
        val areaW = constraints.maxWidth
        val areaH = constraints.maxHeight
        // the page turns when its sentences up to the one being heard (whole) would not fit
        LaunchedEffect(cur?.first, areaW, areaH) {
            val c = cur ?: return@LaunchedEffect
            if (pageStart < 0 || c.first < pageStart) { pageStart = c.first; return@LaunchedEffect }
            val parts = ArrayList<IntRange>().apply { add(c) }
            var at = c.first
            while (parts.size < 30) {
                val prev = nav.sentenceBefore(at) ?: break
                if (prev.first < pageStart || prev.first >= at) break
                parts.add(0, prev); at = prev.first
            }
            val style = TextStyle(fontSize = fontSize, fontWeight = FontWeight.SemiBold, fontFamily = RideColors.serif, lineHeight = fontSize * 1.3f)
            var height = 0
            for (p in parts) {
                height += measurer.measure(nav.substring(p), style, constraints = Constraints(maxWidth = maxOf(1, areaW))).size.height
                height += with(density) { gap.roundToPx() }
            }
            if (height > areaH) pageStart = c.first
        }
        val pieces = run {
            val c = cur ?: return@run emptyList<Piece>()
            val out = ArrayList<Piece>()
            var at = c.first
            for (n in 0 until 14) {
                if (pageStart < 0 || at <= pageStart) break
                val prev = nav.sentenceBefore(at) ?: break
                if (prev.first >= at || prev.first < pageStart || nav.substring(prev).isBlank()) break
                out.add(0, Piece(prev, prev.last + 1, true))
                at = prev.first
            }
            val word = spoken.word
            val heardEnd = if (word != null && word.first in c) word.last + 1 else st.cursor.coerceIn(c.first, c.last + 1)
            if (heardEnd > c.first) out.add(Piece(c, heardEnd, false))
            out
        }
        // the outgoing page keeps its own sentences while it fades (contentKey: a new page, not a new word)
        AnimatedContent(pageStart to pieces, contentKey = { it.first }, transitionSpec = {
            fadeIn(tween(500, delayMillis = 250)) togetherWith (fadeOut(tween(350)) + slideOutVertically(tween(350)) { -it / 12 })
        }, label = "page") { (_, pieces) ->
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(gap)) {
                pieces.forEachIndexed { n, s ->
                    val marked = app.isMarked(s.range)
                    val alpha = if (s.past) maxOf(0.28f, 0.6f - (pieces.size - 1 - n) * 0.08f) else 1f
                    val text = styled(nav.substring(s.range.first until s.shownEnd), s.range.first, concepts, s.past,
                        if (!s.past) spoken.word else null, r, bigSize, pastBig)
                    Text(text, Modifier.fillMaxWidth().drawBehind {
                        if (!marked) return@drawBehind
                        val pad = 6.dp.toPx(); val left = 10.dp.toPx()
                        val tl = Offset(-left, -pad); val sz = Size(size.width + left + pad, size.height + 2 * pad)
                        val cr = CornerRadius(8.dp.toPx())
                        drawRoundRect(r.gold.copy(alpha = if (s.past) 0.09f else 0.16f), tl, sz, cr)
                        drawRoundRect(r.gold.copy(alpha = if (s.past) 0.18f else 0.32f), tl, sz, cr, style = Stroke(1.dp.toPx()))
                        val sw = sz.width * 0.35f
                        val x = tl.x + sz.width * sweep.value
                        if (sweep.value < 1.05f) drawRect(Brush.horizontalGradient(listOf(Color.Transparent, r.gold.copy(alpha = 0.45f), Color.Transparent), x, x + sw),
                            Offset(maxOf(tl.x, x), tl.y), Size((minOf(tl.x + sz.width, x + sw) - maxOf(tl.x, x)).coerceAtLeast(0f), sz.height))
                        drawRoundRect(r.gold, Offset(-w.toPx() * 0.036f, 2.dp.toPx()), Size(3.dp.toPx(), size.height - 4.dp.toPx()), CornerRadius(2.dp.toPx()))
                    }, color = r.paper.copy(alpha = alpha), fontSize = fontSize, fontFamily = RideColors.serif,
                        lineHeight = fontSize * 1.3f, maxLines = if (s.past) Int.MAX_VALUE else 12, overflow = TextOverflow.Clip)
                }
            }
        }
    }
}

/** The concept words amber and larger; the word being heard amber. */
private fun styled(
    t: String, base: Int, concepts: Map<Int, String>, past: Boolean, word: IntRange?, r: RideColors,
    big: androidx.compose.ui.unit.TextUnit, pastBig: androidx.compose.ui.unit.TextUnit,
): AnnotatedString = buildAnnotatedString {
    var i = 0
    while (i < t.length) {
        if (t[i].isLetterOrDigit() && (i == 0 || !t[i - 1].isLetterOrDigit())) {
            var j = i
            while (j < t.length && (t[j].isLetterOrDigit() || t[j] == '\'' || t[j] == '’')) j++
            val abs = base + i
            val concept = concepts[abs] != null
            val heard = word != null && word.first == abs
            when {
                concept -> withStyle(SpanStyle(color = if (past) r.amber.copy(alpha = 0.6f) else r.amber, fontSize = if (past) pastBig else big,
                    fontWeight = FontWeight.SemiBold)) { append(t.substring(i, j)) }
                heard -> withStyle(SpanStyle(color = r.amber)) { append(t.substring(i, j)) }
                else -> append(t.substring(i, j))
            }
            i = j
        } else { append(t[i]); i++ }
    }
}

// MARK: - the rest bar

/** The reading place's buttons: chapter back · sentence back · play · sentence on · chapter on. */
@Composable
fun RestBar(app: AppModel, onJump: (Int, Boolean) -> Unit) {
    val r = LocalRide.current
    val st by app.player.state.collectAsState()
    val p = app.player
    val chapters = p.nav.chapters
    fun chapter(forward: Boolean) {
        val cur = chapters.indexOfLast { it.offset <= p.cursor }
        val j = if (forward) cur + 1 else if (cur >= 0 && p.cursor - chapters[cur].offset > 40) cur else cur - 1
        if (j in chapters.indices) onJump(chapters[j].offset, p.isPlaying)
    }
    @Composable fun key(icon: ImageVector, label: String, enabled: Boolean = true, action: () -> Unit) {
        Box(Modifier.size(44.dp).border(1.dp, r.line, CircleShape).clickable(enabled = enabled, onClick = action), contentAlignment = Alignment.Center) {
            Icon(icon, label, tint = r.paper.copy(alpha = if (enabled) 0.75f else 0.25f), modifier = Modifier.size(20.dp))
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        key(Icons.Filled.SkipPrevious, "Önceki bölüm", chapters.isNotEmpty()) { chapter(false) }
        key(Icons.Filled.FastRewind, "Önceki cümle") { p.skip(false, NavigationUnit.sentence) }
        Box(Modifier.size(58.dp).drawBehind {
            drawCircle(Brush.radialGradient(listOf(r.amber.copy(alpha = 0.45f), Color.Transparent), radius = size.width), radius = size.width * 0.75f)
        }.background(r.amber, CircleShape).clickable { p.toggle() }, contentAlignment = Alignment.Center) {
            Icon(if (st.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (st.isPlaying) "Duraklat" else "Oynat",
                tint = r.onAmber, modifier = Modifier.size(30.dp))
        }
        key(Icons.Filled.FastForward, "Sonraki cümle") { p.skip(true, NavigationUnit.sentence) }
        key(Icons.Filled.SkipNext, "Sonraki bölüm", chapters.isNotEmpty()) { chapter(true) }
    }
}

// MARK: - the book line and the progress

/** The chapter being heard, easy to read on the dark page, and the book under it. A tap opens the contents. */
@Composable
fun RideBookLine(app: AppModel, onContents: () -> Unit, modifier: Modifier = Modifier) {
    val r = LocalRide.current
    val st by app.player.state.collectAsState()
    val spoken by app.player.spoken.collectAsState()
    val found = app.player.nav.chapterTitle(spoken.sentence?.first ?: st.cursor)
    val chapter = if (found == st.title) null else found
    Column(modifier.fillMaxWidth().clickable(onClick = onContents), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (chapter != null) Text(chapter, color = r.paper.copy(alpha = 0.92f), fontFamily = RideColors.serif, fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(st.title, color = r.muted, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The whole book: how far it is, how long was heard and how long is left; the chapters are small ticks on the line. */
@Composable
fun RideProgress(app: AppModel, modifier: Modifier = Modifier) {
    val r = LocalRide.current
    val st by app.player.state.collectAsState()
    val len = maxOf(1, st.length)
    val whole = (st.cursor.toFloat() / len).coerceIn(0f, 1f)
    val total = app.duration(len, app.player.speed)
    val heard = total * whole
    val left = maxOf(0.0, total - heard)
    val starts = app.player.nav.chapters.filter { it.level <= 1 && it.offset > 0 }.map { it.offset.toFloat() / len }
    val shown by animateFloatAsState(whole, tween(400), label = "progress")
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Canvas(Modifier.fillMaxWidth().height(5.dp)) {
            val cr = CornerRadius(size.height / 2)
            drawRoundRect(r.track, cornerRadius = cr)
            drawRoundRect(r.amber, size = Size(maxOf(5.dp.toPx(), size.width * shown), size.height), cornerRadius = cr)
            if (starts.size <= 80) for (s in starts) drawRect(if (s <= shown) r.oled.copy(alpha = 0.55f) else r.muted.copy(alpha = 0.7f),
                Offset(size.width * s - 0.5f, 0f), Size(1f, size.height))
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Text(if (heard < 60) "yeni başladı" else "${Format.duration(heard)} geçti", Modifier.weight(1f), color = r.muted,
                fontFamily = RideColors.mono, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            Text("%${(whole * 100).toInt()}", color = r.paper, fontFamily = RideColors.mono, fontSize = 19.sp, fontWeight = FontWeight.Bold)
            Text(if (left < 30) "bitti sayılır" else "${Format.duration(left)} kaldı", Modifier.weight(1f), color = r.muted,
                fontFamily = RideColors.mono, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1,
                textAlign = androidx.compose.ui.text.style.TextAlign.End)
        }
    }
}

// MARK: - the dock: speed · voice note · mark

/** One key, four speeds: each tap goes 330 → 380 → 430 → 470 → 330 words a minute. */
private val speeds = listOf(330, 380, 430, 470)

@Composable
fun RideDock(app: AppModel, state: RideState, mark: () -> Unit) {
    val r = LocalRide.current
    app.player.state.collectAsState().value
    app.player.spoken.collectAsState().value
    app.store.documents.collectAsState().value
    val cps = app.settings.charsPerSecond
    val now = Format.wpm(cps, app.player.speed)
    val shape = RoundedCornerShape(14.dp)
    val held = remember { mutableStateOf(0) }
    val ring = remember { mutableStateOf(0f) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.width(66.dp).height(60.dp).background(r.well, shape).border(1.dp, r.line, shape).clickable {
            val next = speeds.firstOrNull { it > now + 2 } ?: speeds[0]
            app.setSpeed(next / (cps * 60 / 6.2), documentOnly = app.currentDocument?.speed != null)
            state.say("Hız $next kelime/dk")
        }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("$now", color = r.paper, fontFamily = RideColors.mono, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text("k/dk", color = r.muted, fontFamily = RideColors.mono, fontSize = 10.sp)
        }
        // hold half a second to start (a ring runs round the key), tap to stop
        val on = app.recording
        val ink = if (on) (if (r.day) Color.White else Color(1f, 0.85f, 0.81f)) else r.alert
        Column(Modifier.width(84.dp).height(60.dp)
            .background(if (on) (if (r.day) r.alert else Color(0.227f, 0.098f, 0.071f)) else r.well, shape)
            .border(1.dp, if (on) r.alert else r.alert.copy(alpha = 0.4f), shape)
            .drawRingBehind(ring.value, r.alert, 14.dp, 3.dp)
            .micHold(app, ring, onStart = { state.say("Kayıt başladı · bitirmek için dokun") }, onStop = { state.say("Sesli not kaydedildi") }),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
            Icon(if (on) Icons.Filled.Stop else Icons.Filled.Mic, null, tint = ink, modifier = Modifier.size(20.dp))
            Text(if (on) "Bitir" else "Basılı tut", color = ink, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        }
        val marked = app.spokenSentenceMarked()
        val n = held.value
        Row(Modifier.weight(1f).height(60.dp).background(r.well, shape).border(1.dp, r.gold.copy(alpha = 0.4f), shape)
            .markHold(app, mark, held), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Icon(if (n > 1) Icons.Filled.LinearScale else if (marked) Icons.Filled.FormatClear else Icons.Filled.BorderColor, null,
                tint = r.gold, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(8.dp))
            Text(if (n > 1) "$n cümle" else if (marked) "Kaldır" else "İşaretle", color = r.gold, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

// MARK: - the mark's animation

/** A mark, seen without reading: a gold ring spreads from where the finger touched, sparks rise, a leaf drifts down. */
@Composable
fun MarkBurst(tick: Int, from: Offset, to: Offset) {
    if (tick <= 0) return
    val r = LocalRide.current
    val t = remember(tick) { Animatable(0f) }
    val fall = remember(tick) { Animatable(0f) }
    LaunchedEffect(tick) { launch { t.animateTo(1f, tween(750, easing = FastOutSlowInEasing)) }; fall.animateTo(1f, tween(1100, easing = FastOutSlowInEasing)) }
    Canvas(Modifier.fillMaxSize()) {
        val v = t.value; val f = fall.value
        if (v < 1f) {
            for (k in 0 until 2) {
                val d = (30 + 190 * v * (if (k == 0) 1f else 0.7f)).dp.toPx()
                drawCircle(r.gold.copy(alpha = (1 - v) * (if (k == 0) 0.9f else 0.5f)), d / 2, from, style = Stroke((if (k == 0) 2.5f else 1.5f).dp.toPx()))
            }
            drawCircle(Brush.radialGradient(listOf(r.gold.copy(alpha = 0.55f * (1 - v)), Color.Transparent), from, 70.dp.toPx()), 70.dp.toPx(), from)
            for (i in 0 until 8) {
                val a = i / 8.0 * 2 * Math.PI - Math.PI / 2
                val p = Offset(from.x + (cos(a) * 70 * v).toFloat().dp.toPx(), from.y + ((sin(a) * 70 - 20) * v).toFloat().dp.toPx())
                drawCircle(r.amber.copy(alpha = 1 - v), 2.dp.toPx(), p)
            }
        }
        if (f < 0.98f) {
            val x = from.x + (to.x - from.x) * f + (sin(f * Math.PI * 3) * 24).toFloat().dp.toPx()
            val y = from.y + (to.y - from.y) * f * f
            rotate(f * 220f, Offset(x, y)) {
                val lw = 16.dp.toPx(); val lh = 22.dp.toPx()
                val p = Path().apply {
                    moveTo(x - lw / 2, y + lh / 2)
                    quadraticBezierTo(x - lw / 2, y - lh / 2, x + lw / 2, y - lh / 2)
                    quadraticBezierTo(x + lw / 2, y + lh / 2, x - lw / 2, y + lh / 2)
                }
                drawPath(p, Brush.verticalGradient(listOf(r.gold, r.amber), y - lh / 2, y + lh / 2))
            }
        }
    }
}

/** A falling leaf's shape, small, for the leaves by the sediment. */
@Composable
fun LeafDot(color: Color, w: Dp, h: Dp) {
    Canvas(Modifier.size(w, h)) {
        val p = Path().apply {
            moveTo(0f, size.height)
            quadraticBezierTo(0f, 0f, size.width, 0f)
            quadraticBezierTo(size.width, size.height, 0f, size.height)
        }
        drawPath(p, color)
    }
}

// MARK: - the contents, while riding

/**
 * The chapters; a row tapped shows that place's opening lines, with ▶ to read from there. The reading place stays
 * where it is until ▶ is pressed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RideContents(app: AppModel, onJump: (Int, Boolean) -> Unit, onDismiss: () -> Unit) {
    val r = LocalRide.current
    val nav = app.player.nav
    var peek by remember { mutableStateOf<Int?>(null) }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet, containerColor = r.panel, contentColor = r.paper) {
        val at = peek
        if (at == null) {
            Text("İçindekiler", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            if (nav.chapters.isEmpty()) Text("Bu belgede bölüm yok", color = r.muted, modifier = Modifier.padding(20.dp))
            val current = nav.chapterIndex(app.player.cursor)
            LazyColumn(Modifier.padding(bottom = 24.dp)) {
                itemsIndexed(nav.chapters) { i, c ->
                    Text(c.title, Modifier.fillMaxWidth().clickable { peek = c.offset }
                        .padding(start = (20 + 14 * (c.level - 1).coerceAtLeast(0)).dp, end = 20.dp, top = 12.dp, bottom = 12.dp),
                        color = if (i == current) r.amber else r.paper, fontFamily = RideColors.serif, fontSize = 16.sp,
                        fontWeight = if (i == current) FontWeight.SemiBold else FontWeight.Normal, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        } else {
            val end = minOf(nav.length, at + 700)
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(nav.chapterTitle(at) ?: "Bu yer", color = r.paper, fontFamily = RideColors.serif, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                Text(nav.substring(at until end) + if (end < nav.length) "…" else "", Modifier.heightIn(max = 340.dp).verticalScroll(rememberScrollState()),
                    color = r.paper.copy(alpha = 0.85f), fontFamily = RideColors.serif, fontSize = 18.sp, lineHeight = 26.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    val shape = RoundedCornerShape(14.dp)
                    Box(Modifier.weight(1f).height(52.dp).background(r.raise, shape).clickable { onDismiss() }, contentAlignment = Alignment.Center) {
                        Text("Kaldığım yerde kal", color = r.paper, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Row(Modifier.weight(1f).height(52.dp).background(if (r.day) r.raise else Color(0.169f, 0.129f, 0.086f), shape)
                        .border(1.dp, r.amber, shape).clickable { onJump(at, true); onDismiss() },
                        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.PlayArrow, null, tint = r.amber)
                        Text("Buradan oku", color = r.amber, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
    }
}
