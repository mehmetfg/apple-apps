// Müzik modu's screen (port of MusicModeView.swift). Three contents: Cümleler (no voice, the book's sentences with
// the music), Yalnız ritim (no text, only the backdrop moving with the beat: time to think) and Dinle (the book read
// aloud, the heard words set as kinetic type). A music break opens it on Yalnız ritim. In Cümleler each beat brings
// the next words of a sentence in, the finished sentence stays a few beats, then the next one comes. A tap stops it
// and shows the sentence calmly with why it matters, its chapter and the book's main idea; a sideways swipe goes to
// the next or the previous sentence.
package com.fatihgocgun.wisepath.music

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.move.RoadStatus
import com.fatihgocgun.wisepath.settings.MusicMix
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

enum class MusicContent(val label: String) {
    lines("Cümleler"), rhythm("Yalnız ritim"), listen("Dinle (kitap okunur)");
    companion object { fun of(raw: String) = entries.firstOrNull { it.name == raw } ?: lines }
}

enum class MusicBackdrop(val label: String) {
    circle("Daire"), day("Gündüz"), breath("Nefes"), aurora("Aurora"), drop("Damla"), pulse("Nabız"),
    lissajous("Lissajous"), tunnel("Tünel"), black("Siyah"), glow("Işık"), dusk("Gün batımı");
    companion object { fun of(raw: String) = entries.firstOrNull { it.name == raw } ?: circle }
}

private val tr = Locale("tr", "TR")

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MusicModeScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val app = remember { AppModel.get(context) }
    val s = app.settings
    val scope = rememberCoroutineScope()
    val beat = remember { BeatTracker(context, scope) }
    val st by app.player.state.collectAsState()
    // a music break opened it: the rhythm alone, and the break's time left
    val fromBreak = remember { app.player.state.value.breakEnds != null }
    val content = if (fromBreak) MusicContent.rhythm else MusicContent.of(s.musicContent)
    val backdrop = MusicBackdrop.of(s.musicBackdrop)
    val day = backdrop == MusicBackdrop.day
    val amber = if (day) Color(0.78f, 0.36f, 0.03f) else Color(0.98f, 0.72f, 0.30f)
    val paper = if (day) Color(0.125f, 0.105f, 0.085f) else Color(0.97f, 0.95f, 0.90f)
    val page = if (day) Color(0.965f, 0.945f, 0.905f) else Color.Black
    val chip = if (day) Color.Black.copy(alpha = 0.06f) else Color.White.copy(alpha = 0.08f)

    var lines by remember { mutableStateOf<List<MusicLine>>(emptyList()) }
    var insight by remember { mutableStateOf<TeoriaInsight?>(null) }
    var title by remember { mutableStateOf("") }
    var loaded by remember { mutableStateOf(false) }
    var index by remember { mutableIntStateOf(0) }
    var shown by remember { mutableIntStateOf(0) }
    var hold by remember { mutableIntStateOf(0) }
    var paused by remember { mutableStateOf(false) }
    var phraseIndex by remember { mutableIntStateOf(0) }
    var phraseShown by remember { mutableIntStateOf(0) }
    val flash = remember { Animatable(0f) }
    val bump = remember { Animatable(0f) }
    var wasReading by remember { mutableStateOf(false) }

    val line = if (lines.isEmpty()) null else lines[index % lines.size]
    val words = line?.text?.split(' ')?.filter { it.isNotEmpty() } ?: emptyList()
    val kinetic = s.musicKinetic
    val phrases = remember(line?.id, index) { line?.let { KineticPhrase.phrases(it.text, index) } ?: emptyList() }
    val phrase = phrases.getOrNull(phraseIndex)
    val chunk = maxOf(1, minOf(3, words.size / 10))

    // the microphone, asked for once when the rhythm should be heard
    val micLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) { beat.stop(); beat.start(true) }
    }

    LaunchedEffect(Unit) {
        val id = app.player.documentID ?: app.openDocumentID
        val doc = id?.let { app.store.document(it) }
        val c = id?.let { app.store.content(it) }
        if (doc != null && c != null) {
            title = doc.title
            insight = MusicPool.insightFor?.invoke(doc.title)
            val chapters = c.chapters
            lines = MusicPool.build(doc, c.text, insight) { at -> chapters.lastOrNull { it.offset <= at }?.title }
        }
        loaded = true
    }
    val view = LocalView.current
    DisposableEffect(Unit) {
        // the music comes to the front: reading pauses (not in a break, and not when listening); mixing is turned on
        // so reading again puts the music behind the voice instead of stopping it
        if (s.musicMix == MusicMix.off) { s.musicMix = MusicMix.mix; app.applyAudioSettings() }
        if (content != MusicContent.listen && !fromBreak && app.player.isPlaying) { wasReading = true; app.player.pause() }
        view.keepScreenOn = true
        beat.start(s.musicMic)
        if (s.musicMic && !BeatTracker.micAllowed(context)) micLauncher.launch(Manifest.permission.RECORD_AUDIO)
        onDispose {
            beat.stop()
            view.keepScreenOn = false
            // closing: reading goes on where it stopped, the music behind the voice
            if (wasReading && !app.player.isPlaying) app.player.resume()
        }
    }
    // a break that ends closes the rhythm (reading goes on by itself)
    if (fromBreak) LaunchedEffect(st.breakEnds) { if (st.breakEnds == null) onClose() }

    fun step(by: Int) {
        if (lines.isEmpty()) return
        index = Math.floorMod(index + by, lines.size)
        shown = 0; hold = 0; phraseIndex = 0; phraseShown = 0
        paused = false; beat.paused = false
    }

    // each beat
    LaunchedEffect(beat.beat) {
        if (beat.beat == 0 || paused) return@LaunchedEffect
        bump.snapTo(1f)
        if (content == MusicContent.lines && line != null) {
            if (kinetic) {
                val p = phrase
                if (p == null) step(1)
                else if (phraseShown < p.beats) {
                    phraseShown++
                    if (phraseShown - 1 == p.key) { flash.snapTo(1f) }
                } else {
                    hold++
                    val last = phraseIndex >= phrases.size - 1
                    if (hold >= (if (last) 3 else 1)) { if (last) step(1) else { phraseIndex++; phraseShown = 0; hold = 0 } }
                }
            } else if (shown < words.size) shown = minOf(words.size, shown + chunk)
            else { hold++; if (hold >= 5) step(1) }
        }
        if (flash.value > 0f) launch { flash.animateTo(0f, tween(450)) }
        bump.animateTo(0f, tween(380))
    }

    val input = BeatInput(beat.lastBeatAt, beat.bpm, beat.level, beat.beat, paused)

    BoxWithConstraints(Modifier.fillMaxSize().background(page)
        .pointerInput(content) {
            detectTapGestures {
                when (content) {
                    MusicContent.lines -> { paused = !paused; beat.paused = paused }
                    MusicContent.listen -> app.player.toggle()
                    MusicContent.rhythm -> {}
                }
            }
        }
        .pointerInput(content, lines.size) {
            var dx = 0f
            detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = {
                if (content == MusicContent.lines && kotlin.math.abs(dx) > 30.dp.toPx()) step(if (dx < 0) 1 else -1)
            }) { _, d -> dx += d }
        }) {
        val w = maxWidth; val h = maxHeight
        // the backdrop
        Box(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
            when (backdrop) {
                MusicBackdrop.circle -> RadialBars(input, Modifier.size(w).alpha(if (paused) 0.12f else 0.85f))
                MusicBackdrop.day -> RadialBars(input, Modifier.size(w).alpha(if (paused) 0.15f else 0.9f), day = true)
                MusicBackdrop.black -> RhythmBars(input, Modifier.fillMaxWidth().height(h * 0.12f).align(Alignment.BottomCenter).padding(bottom = 44.dp)
                    .alpha(if (paused) 0.1f else 0.45f))
                MusicBackdrop.glow -> Glow(index, bump.value, input, paused)
                MusicBackdrop.dusk -> Dusk(index, bump.value, input, h)
                MusicBackdrop.aurora -> AuroraVisual(input, Modifier.fillMaxSize())
                MusicBackdrop.drop -> DropVisual(input, Modifier.fillMaxSize())
                MusicBackdrop.pulse -> PulseVisual(input, Modifier.fillMaxSize())
                MusicBackdrop.lissajous -> LissajousVisual(input, Modifier.fillMaxSize())
                MusicBackdrop.tunnel -> TunnelVisual(input, Modifier.fillMaxSize())
                MusicBackdrop.breath -> BreathVisual(input, Modifier.fillMaxSize())
            }
        }
        val stage = DpSize(w - 52.dp, h * 0.6f)
        if (content == MusicContent.listen) {
            KineticListening(stage, amber, paper, glow = !day, mask = s.kineticMask, page = page,
                modifier = Modifier.align(Alignment.Center).alpha(if (st.isPlaying) 1f else 0.45f))
        }
        if (content == MusicContent.rhythm && fromBreak) st.breakEnds?.let { ends -> BreakClock(ends, paper, Modifier.align(Alignment.BottomCenter).padding(bottom = 60.dp)) }
        if (content == MusicContent.lines && loaded && line == null) Empty(amber, paper, Modifier.align(Alignment.Center))
        if (content == MusicContent.lines && line != null && !paused) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                val mark = line.kind == MusicLine.Kind.mark
                Text(line.label.uppercase(tr), Modifier.border(1.dp, (if (mark) amber else paper).copy(alpha = 0.35f), CircleShape)
                    .padding(horizontal = 10.dp, vertical = 4.dp), color = if (mark) amber else paper.copy(alpha = 0.55f),
                    fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.4.sp)
                if (kinetic) {
                    KineticStage(phrase, "${line.id}-${phrase?.id}", phraseShown, stage, amber, paper, !day, s.kineticMask, page)
                } else {
                    // the outgoing sentence keeps its own words while it fades (contentKey: a new line, not a new word count)
                    AnimatedContent(Triple(line, words, shown), contentKey = { it.first.id },
                        transitionSpec = { fadeIn() togetherWith (fadeOut() + slideOutVertically { -it / 6 }) }, label = "line") { (l, w, n) ->
                        Flow(w, n, maxOf(1, minOf(3, w.size / 10)), size(l), amber, paper, day, Modifier.padding(horizontal = 26.dp))
                    }
                }
            }
        }
        Box(Modifier.fillMaxSize().background(amber.copy(alpha = flash.value * (if (day) 0.07f else 0.16f))))
        AnimatedVisibility(paused && content == MusicContent.lines && line != null, enter = fadeIn() + scaleIn(initialScale = 0.96f), exit = fadeOut()) {
            line?.let { Card(it, insight, amber, paper, day) }
        }
        // the chrome
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp), verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(40.dp).background(chip, CircleShape).clickable(onClick = onClose), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Close, "Müzik modundan çık", tint = paper.copy(alpha = 0.8f), modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.weight(1f))
                RoadStatus(app, Modifier.widthIn(max = 230.dp), label = if (fromBreak) "Ara · müzik" else "Müzik modu", book = title,
                    ink = paper.copy(alpha = 0.6f), dim = paper.copy(alpha = 0.4f))
                Spacer(Modifier.weight(1f))
                Tempo(beat, amber, paper, chip, bump.value) { on ->
                    s.musicMic = on
                    beat.stop(); beat.start(on)
                    if (on && !BeatTracker.micAllowed(context)) micLauncher.launch(Manifest.permission.RECORD_AUDIO)
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp).alpha(0.8f), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End)) {
                Box(Modifier.size(36.dp).background(chip, CircleShape).clickable {
                    val all = MusicBackdrop.entries
                    s.musicBackdrop = all[(all.indexOf(backdrop) + 1) % all.size].name
                }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Palette, "Arka plan: ${backdrop.label}. Dokun: sonraki", tint = paper.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
                }
                if (!fromBreak) ContentMenu(content, paper, chip) { c ->
                    s.musicContent = c.name; paused = false; beat.paused = false
                    if (c == MusicContent.listen) { if (!app.player.isPlaying) app.player.play() }
                    else if (app.player.isPlaying) app.player.pause()
                }
                if (content == MusicContent.lines || content == MusicContent.listen) {
                    // Akış → Kinetik → Perde (Dinle has no Akış: Kinetik ↔ Perde)
                    val name = if (content == MusicContent.lines && !kinetic) "Akış" else if (s.kineticMask) "Perde" else "Kinetik"
                    Box(Modifier.height(36.dp).background(chip, CircleShape).clickable {
                        if (content == MusicContent.listen) s.kineticMask = !s.kineticMask
                        else if (!s.musicKinetic) { s.musicKinetic = true; s.kineticMask = false }
                        else if (!s.kineticMask) s.kineticMask = true
                        else { s.musicKinetic = false; s.kineticMask = false }
                        phraseIndex = 0; phraseShown = 0; shown = 0; hold = 0
                    }.padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                        Text(name, color = paper.copy(alpha = 0.85f), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 10.dp)) {
                val hint = paper.copy(alpha = 0.62f)
                when (content) {
                    MusicContent.lines -> {
                        Text(if (paused) "dokun: sürdür" else "dokun: dur · kaydır: sonraki", color = hint, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                        Spacer(Modifier.weight(1f))
                        if (lines.isNotEmpty()) Text("${index % lines.size + 1}/${lines.size}", color = hint, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    }
                    MusicContent.rhythm -> Text(if (fromBreak) "ara bitince okuma kendiliğinden sürer" else "yazı yok · yalnız ritim",
                        color = hint, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    MusicContent.listen -> {
                        Text(if (st.isPlaying) "dokun: duraklat" else "dokun: oku", color = hint, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                        Spacer(Modifier.weight(1f))
                        app.player.nav.chapterTitle(st.cursor)?.let {
                            Text(it, Modifier.widthIn(max = 200.dp), color = hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

private fun size(line: MusicLine): Float { val n = line.text.length; return if (n < 70) 38f else if (n < 140) 31f else if (n < 240) 26f else 22f }

/** Akış: the words come in a few a beat, from large and blurred to their place, in centred lines. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Flow(words: List<String>, shown: Int, chunk: Int, size: Float, amber: Color, paper: Color, day: Boolean, modifier: Modifier) {
    FlowRow(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy((size * 0.28f).dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy((size * 0.18f).dp)) {
        for (i in 0 until minOf(shown, words.size)) androidx.compose.runtime.key(i) {
            val t = remember { Animatable(0f) }
            LaunchedEffect(Unit) { t.animateTo(1f, spring(dampingRatio = 0.7f, stiffness = 300f)) }
            val fresh = i >= shown - chunk
            val v = t.value
            Text(words[i], Modifier.graphicsLayer {
                val sc = 1 + (1 - v) * 0.45f; scaleX = sc; scaleY = sc; alpha = v.coerceIn(0f, 1f); translationY = (1 - v) * 10.dp.toPx()
            }, color = if (fresh) amber else paper, fontSize = size.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif,
                style = androidx.compose.ui.text.TextStyle(shadow = if (fresh && !day) Shadow(amber.copy(alpha = 0.55f), blurRadius = 28f) else null))
        }
    }
}

/** Stopped: the sentence whole and quiet, why it matters, its chapter, and the book's main idea. */
@Composable
private fun Card(line: MusicLine, insight: TeoriaInsight?, amber: Color, paper: Color, day: Boolean) {
    Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 90.dp)) {
        Column(Modifier.fillMaxWidth().background((if (day) Color.White else Color(0xFF1C1C1E)).copy(alpha = 0.75f), RoundedCornerShape(24.dp)).padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(line.label.uppercase(tr), color = amber, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
                line.chapter?.let { Text("· $it", color = paper.copy(alpha = 0.5f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            Text(line.text, color = paper, fontSize = 24.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Serif, lineHeight = 32.sp)
            line.why?.let { why ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Lightbulb, null, tint = paper.copy(alpha = 0.75f), modifier = Modifier.size(18.dp))
                    Text(why, color = paper.copy(alpha = 0.75f), fontSize = 15.sp)
                }
            }
            val core = insight?.core
            if (core != null && (core.theme != null || core.claim != null)) {
                HorizontalDivider(color = paper.copy(alpha = 0.15f))
                Text("KİTABIN ANA FİKRİ", color = paper.copy(alpha = 0.45f), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
                core.theme?.let { Text(it, color = paper.copy(alpha = 0.9f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif) }
                core.claim?.let { Text(it, color = paper.copy(alpha = 0.7f), fontSize = 15.sp, lineHeight = 21.sp) }
            }
        }
    }
}

@Composable
private fun Empty(amber: Color, paper: Color, modifier: Modifier) {
    Column(modifier.padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.MusicNote, null, tint = amber, modifier = Modifier.size(36.dp))
        Text("Bu kitapta gösterilecek cümle yok", color = paper, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text("Okurken işaretlediğin cümleler burada müzikle akar. Kitap Teoria'da özetlendiyse can alıcı cümleleri ve ana fikri de gelir.",
            color = paper.copy(alpha = 0.6f), fontSize = 14.sp, textAlign = TextAlign.Center)
    }
}

/** The break's time left, small and quiet under the rhythm. */
@Composable
private fun BreakClock(ends: Long, paper: Color, modifier: Modifier) {
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    val left = maxOf(0L, (ends - now + 500) / 1000)
    Text("${left / 60}:%02d".format(left % 60), modifier, color = paper.copy(alpha = 0.45f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
}

/** Tap in time to give the tempo; hold for the microphone switch. The dot blinks on every beat. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Tempo(beat: BeatTracker, amber: Color, paper: Color, chip: Color, bump: Float, onMic: (Boolean) -> Unit) {
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.height(36.dp).background(chip, CircleShape).combinedClickable(onClick = { beat.tap() }, onLongClick = { menu = true })
            .padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(7.dp).background(amber.copy(alpha = 0.25f + 0.75f * bump), CircleShape))
            Icon(if (beat.source == BeatTracker.Source.microphone) Icons.Filled.Mic else Icons.Filled.Timer, null, tint = paper.copy(alpha = 0.85f),
                modifier = Modifier.size(14.dp))
            Text("${beat.bpm.toInt()}", color = paper.copy(alpha = 0.85f), fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
        DropdownMenu(menu, { menu = false }) {
            val on = AppModel.get(context).settings.musicMic
            DropdownMenuItem(text = { Text("Ritmi mikrofondan dinle") }, leadingIcon = { Checkbox(on, null) },
                onClick = { menu = false; onMic(!on) })
            Text("Müzik kulaklıktaysa mikrofon duymaz: düğmeye ritimle 4 kez dokun.", Modifier.padding(horizontal = 16.dp, vertical = 8.dp).widthIn(max = 260.dp),
                fontSize = 12.sp)
        }
    }
}

/** Cümleler · Yalnız ritim · Dinle. Going to Dinle starts the voice; leaving it stops the voice. */
@Composable
private fun ContentMenu(content: MusicContent, paper: Color, chip: Color, onPick: (MusicContent) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Box(Modifier.size(36.dp).background(chip, CircleShape).clickable { open = true }, contentAlignment = Alignment.Center) {
            Icon(when (content) { MusicContent.lines -> Icons.Filled.FormatQuote; MusicContent.rhythm -> Icons.Filled.GraphicEq; MusicContent.listen -> Icons.Filled.Headphones },
                "İçerik: ${content.label}", tint = paper.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
        }
        DropdownMenu(open, { open = false }) {
            MusicContent.entries.forEach { c ->
                DropdownMenuItem(text = { Text(c.label, fontWeight = if (c == content) FontWeight.Bold else FontWeight.Normal) },
                    onClick = { open = false; onPick(c) })
            }
        }
    }
}

/** Two slow, warm light pools whose colour drifts with each sentence; they swell on the beat; bars behind the text. */
@Composable
private fun Glow(index: Int, bump: Float, input: BeatInput, paused: Boolean) {
    val now = rememberFrameTime(paused)
    val hue = ((index * 47) % 360).toFloat()
    val hueA by animateFloatAsState(hue, tween(1600), label = "glow")
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = maxWidth; val h = maxHeight
        val t = now / 1000.0
        Box(Modifier.fillMaxSize().scale(1 + 0.06f * bump).blur(30.dp)) {
            Box(Modifier.size(w * 1.2f).align(Alignment.Center).graphicsLayer {
                translationX = (kotlin.math.cos(t / 7) * w.toPx() * 0.18).toFloat()
                translationY = (kotlin.math.sin(t / 9) * h.toPx() * 0.12 - h.toPx() * 0.12).toFloat()
            }.background(Brush.radialGradient(listOf(Color.hsv(hueA, 0.75f, 0.55f).copy(alpha = 0.55f), Color.Transparent)), CircleShape))
            Box(Modifier.size(w * 1.1f).align(Alignment.Center).graphicsLayer {
                translationX = (kotlin.math.sin(t / 8) * w.toPx() * 0.2).toFloat()
                translationY = (kotlin.math.cos(t / 6) * h.toPx() * 0.1 + h.toPx() * 0.18).toFloat()
            }.background(Brush.radialGradient(listOf(Color.hsv((hueA + 43f) % 360f, 0.7f, 0.45f).copy(alpha = 0.5f), Color.Transparent)), CircleShape))
        }
        RhythmBars(input, Modifier.fillMaxWidth().height(h * 0.5f).align(Alignment.Center).alpha(if (paused) 0.1f else 0.28f))
    }
}

/** A deep violet-to-ember sky that brightens on the beat. */
@Composable
private fun Dusk(index: Int, bump: Float, input: BeatInput, h: androidx.compose.ui.unit.Dp) {
    val hue = ((index * 23) % 60).toFloat()
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0.07f, 0.02f, 0.14f),
        Color.hsv((280f + hue) % 360f, 0.6f, 0.28f), Color.hsv((14f + hue) % 360f, 0.8f, 0.48f + 0.14f * bump))))) {
        RhythmBars(input, Modifier.fillMaxWidth().height(h * 0.16f).align(Alignment.BottomCenter).padding(bottom = 40.dp).alpha(0.35f))
    }
}
