// The reader's note parts (port of NoteViews.swift): the microphone button, the recording strip, the "saved" toast and
// the note sheet (listen, read, write, delete).
package com.fatihgocgun.wisepath.notes

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.ui.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** How long the microphone key is held before a recording starts: a brush of the thumb does nothing. */
const val MIC_HOLD_MS = 500L

private val recordRed = Color(0xFFFF3B30)
private val okGreen = Color(0xFF34C759)

/**
 * Record a voice note about the sentence being read. Held for half a second (a ring fills while the finger is down)
 * it starts; while recording, one tap ends it and saves. With `holdToStart = false` a tap starts too.
 * The microphone permission is asked for when missing; once given, the recording starts.
 */
@Composable
fun MicButton(modifier: Modifier = Modifier, size: Dp = 58.dp, holdToStart: Boolean = true) {
    val app = AppModel.get(LocalContext.current)
    val on = app.recording
    var pressing by remember { mutableStateOf(false) }
    var hint by remember { mutableStateOf(false) }
    val held = remember { booleanArrayOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) app.toggleVoiceNote() else app.message = "Kayıt başlatılamadı. Mikrofon iznini verin."
    }
    val start = {
        if (!app.recorder.isRecording) {
            if (app.recorder.hasPermission) app.toggleVoiceNote() else permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    val ring by animateFloatAsState(if (pressing && !on) 1f else 0f,
        if (pressing) tween(MIC_HOLD_MS.toInt(), easing = androidx.compose.animation.core.LinearEasing) else tween(150), label = "hold")
    val pulse = rememberInfiniteTransition(label = "pulse").animateFloat(1f, 1.35f,
        infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "pulse")
    val accent = MaterialTheme.colorScheme.primary
    LaunchedEffect(hint) { if (hint) { delay(1600); hint = false } }
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        if (on) Box(Modifier.fillMaxSize().scale(pulse.value).clip(CircleShape).background(recordRed.copy(alpha = 0.25f)))
        Box(
            Modifier.fillMaxSize().shadow(8.dp, CircleShape).clip(CircleShape).background(if (on) recordRed else accent)
                .pointerInput(on, holdToStart) {
                    detectTapGestures(
                        onPress = {
                            held[0] = false
                            if (on || !holdToStart) return@detectTapGestures
                            pressing = true
                            val up = withTimeoutOrNull(MIC_HOLD_MS) { tryAwaitRelease() }
                            if (up == null) { held[0] = true; pressing = false; start(); tryAwaitRelease() }
                            pressing = false
                        },
                        onTap = {
                            if (held[0]) { held[0] = false; return@detectTapGestures }
                            when {
                                on -> app.toggleVoiceNote()
                                !holdToStart -> start()
                                else -> hint = true
                            }
                        },
                    )
                }
                .semantics {
                    contentDescription = if (on) "Sesli notu bitir" else "Sesli not"
                    onClick(if (on) "Sesli notu bitir" else "Kaydı başlat") { if (on) app.toggleVoiceNote() else start(); true }
                },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.fillMaxSize().padding(3.dp)) {
                if (ring > 0f) {
                    val w = 3.5.dp.toPx()
                    rotate(-90f) {
                        drawArc(Color.White, 0f, 360f * ring, false, Offset(w / 2, w / 2), Size(this.size.width - w, this.size.height - w),
                            style = Stroke(w, cap = StrokeCap.Round))
                    }
                }
            }
            Icon(if (on) Icons.Filled.Stop else Icons.Filled.Mic, null, tint = Color.White, modifier = Modifier.size(size * 0.45f))
        }
        if (hint) {
            Text("Kayıt için basılı tut", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false,
                modifier = Modifier.wrapContentSize(unbounded = true).offset(x = 50.dp, y = -(size / 2 + 22.dp))
                    .clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(horizontal = 10.dp, vertical = 6.dp))
        }
    }
}

/** The "Not kaydedildi" toast and the recording strip, drawn over the reader and the ride screen. */
@Composable
fun NoteOverlays(modifier: Modifier = Modifier) {
    val app = AppModel.get(LocalContext.current)
    var sheet by remember { mutableStateOf<String?>(null) }
    Box(modifier.fillMaxSize()) {
        AnimatedVisibility(app.recording, Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp),
            enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
            RecordingStrip(app)
        }
        val toast = app.noteToast
        AnimatedVisibility(toast != null, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 96.dp),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
            var last by remember { mutableStateOf(toast) }
            if (toast != null) last = toast
            last?.let { t -> NoteToastView(t) { sheet = t.id; app.noteToast = null } }
        }
        LaunchedEffect(toast) {
            val t = toast ?: return@LaunchedEffect
            delay(if (t.text.isEmpty()) 6000 else 4000)
            if (app.noteToast == t) app.noteToast = null
        }
    }
    sheet?.let { NoteSheet(it) { sheet = null } }
}

/** While recording: how long it has run; a tap ends it, ✕ throws it away. */
@Composable
private fun RecordingStrip(app: AppModel) {
    var started by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        started = System.currentTimeMillis()
        while (true) { now = System.currentTimeMillis(); delay(1000) }
    }
    val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
    Row(
        Modifier.padding(horizontal = 12.dp).fillMaxWidth().shadow(6.dp, RoundedCornerShape(18.dp)).clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable { app.finishVoiceNote() }
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(recordRed))
        Text(Format.clock((now - started) / 1000.0), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Icon(Icons.Filled.Mic, null, tint = Color(0xFFFF9500), modifier = Modifier.size(15.dp))
        Text("Mikrofon", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9500), maxLines = 1)
        Text("bitirmek için dokun", fontSize = 14.sp, color = dim, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                .clickable { app.cancelVoiceNote() }.semantics { contentDescription = "Kaydı at" },
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Close, null, modifier = Modifier.size(14.dp)) }
    }
}

/** "Saved": length and, once written, the note's text. Tap to open it. */
@Composable
private fun NoteToastView(t: com.fatihgocgun.wisepath.NoteToast, onOpen: () -> Unit) {
    Row(
        Modifier.padding(horizontal = 12.dp).fillMaxWidth().shadow(6.dp, RoundedCornerShape(18.dp)).clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onOpen)
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Icon(Icons.Filled.CheckCircle, null, tint = okGreen, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Not kaydedildi" + (t.seconds?.let { " · " + Format.clock(it) } ?: ""), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(t.text.ifEmpty { "Yazıya dökülüyor…" }, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** The note sheet for one note id: listen, read, edit the text, delete. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteSheet(noteId: String, onDismiss: () -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val notes by app.notes.notes.collectAsState()
    val note = notes.firstOrNull { it.id == noteId }
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val scope = rememberCoroutineScope()
    val audio = remember { NoteAudio() }
    DisposableEffect(Unit) { onDispose { audio.stop() } }
    var text by remember(noteId) { mutableStateOf(note?.text ?: "") }
    val close: () -> Unit = { audio.stop(); scope.launch { state.hide() }.invokeOnCompletion { onDismiss() } }
    val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)

    ModalBottomSheet(onDismissRequest = { audio.stop(); onDismiss() }, sheetState = state) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = close) { Text("Vazgeç") }
                Text(if (note?.hasVoice == true) "Sesli not" else "Not", fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                TextButton(onClick = {
                    if (note != null && text.trim() != note.text) app.notes.setText(note.id, text, if (note.hasVoice) "edited" else null)
                    close()
                }, enabled = note != null) { Text("Kaydet", fontWeight = FontWeight.Bold) }
            }
            if (note == null) {
                Text("Not bulunamadı.", color = dim)
                return@Column
            }
            Text("“${note.quote.take(400)}”", fontSize = 16.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, color = dim)
            if (note.hasVoice) {
                val playing = audio.playingID == note.id
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(46.dp).clip(CircleShape).background(Palette.play).clickable {
                            if (app.player.isPlaying) app.player.pause()
                            audio.toggle(note.id, app.notes.audioFile(note))
                        }.semantics { contentDescription = if (playing) "Duraklat" else "Sesli notu dinle" },
                        contentAlignment = Alignment.Center,
                    ) { Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(22.dp)) }
                    Spacer(Modifier.width(12.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("Sesli not · " + Format.clock(note.seconds ?: 0.0), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        val sub = when {
                            note.transcript == "device" -> "Telefonda yazıya döküldü; Mac'te Whisper düzeltir."
                            note.text.isEmpty() -> "Henüz yazıya dökülmedi."
                            else -> ""
                        }
                        if (sub.isNotEmpty()) Text(sub, fontSize = 12.sp, color = dim)
                    }
                }
            }
            OutlinedTextField(
                text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 110.dp), minLines = 4, maxLines = 14,
                placeholder = { Text(if (note.hasVoice) "Dökümü düzelt ya da ekle" else "Aklına geleni yaz") },
                shape = RoundedCornerShape(12.dp),
            )
            Text(Format.date(note.date, "d MMM yyyy HH:mm") + (note.chapterTitle?.let { " · $it" } ?: ""), fontSize = 12.sp, color = dim)
            TextButton(onClick = { audio.stop(); app.notes.delete(note.id); close() }) {
                Icon(Icons.Filled.Delete, null, tint = recordRed, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Notu sil", color = recordRed)
            }
        }
    }
}

@Suppress("unused") private val unusedInsets = WindowInsets
