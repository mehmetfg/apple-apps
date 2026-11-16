// The reader's panels in the Voice Dream manner (port of Views/Panels.swift): Konumlar (contents, bookmarks,
// marks, notes), search, Ses Ayarları, Görsel Ayarlar, the speed card and the selection menu. Each setting has exactly
// one home: speed, voice, tuning, music and reading behaviour in Ses Ayarları; fonts, colours and the cursor in
// Görsel Ayarlar.
package com.fatihgocgun.wisepath.ui.reader

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.TextFold
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.model.HighlightColor
import com.fatihgocgun.wisepath.settings.CursorPosition
import com.fatihgocgun.wisepath.settings.EndBehavior
import com.fatihgocgun.wisepath.settings.MarkColor
import com.fatihgocgun.wisepath.settings.MusicMix
import com.fatihgocgun.wisepath.settings.PageDim
import com.fatihgocgun.wisepath.settings.ReaderFont
import com.fatihgocgun.wisepath.settings.ReaderTheme
import com.fatihgocgun.wisepath.settings.Settings
import com.fatihgocgun.wisepath.settings.VoiceTune
import com.fatihgocgun.wisepath.speech.VoiceCatalog
import com.fatihgocgun.wisepath.speech.VoiceInfo
import com.fatihgocgun.wisepath.ui.Routes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Sheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp), content = content)
    }
}

@Composable
fun SectionLabel(t: String) = Text(t.uppercase(Format.tr), Modifier.padding(top = 18.dp, bottom = 6.dp),
    style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)

@Composable
fun SwitchRow(title: String, checked: Boolean, note: String? = null, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title)
            note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
        }
        Switch(checked, onChange)
    }
}

@Composable
fun SliderRow(title: String, value: Double, range: ClosedFloatingPointRange<Double>, steps: Int = 0, shown: (Double) -> String, onChange: (Double) -> Unit) {
    Column(Modifier.padding(vertical = 4.dp)) {
        Row { Text(title, Modifier.weight(1f)); Text(shown(value), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold) }
        Slider(value.toFloat(), { onChange(it.toDouble()) }, valueRange = range.start.toFloat()..range.endInclusive.toFloat(), steps = steps)
    }
}

@Composable
fun <T> ChoiceRow(options: List<T>, selected: T, label: (T) -> String, onPick: (T) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { o -> FilterChip(selected = o == selected, onClick = { onPick(o) }, label = { Text(label(o)) }) }
    }
}

// MARK: - Konumlar

@Composable
fun PlacesSheet(app: AppModel, doc: DocumentRecord, onDismiss: () -> Unit, onGo: (Int, Boolean) -> Unit, onMove: (Int) -> Unit) {
    val nav = app.player.nav
    val notes by app.notes.notes.collectAsState()
    val s by app.player.state.collectAsState()
    var tab by remember { mutableIntStateOf(0) }
    Sheet(onDismiss) {
        Text("Konumlar", style = MaterialTheme.typography.titleLarge)
        TabRow(selectedTabIndex = tab, containerColor = Color.Transparent) {
            listOf("İçindekiler", "Yer imleri", "İşaretler", "Notlar").forEachIndexed { i, t -> Tab(tab == i, { tab = i }, text = { Text(t, maxLines = 1) }) }
        }
        Box(Modifier.heightIn(max = 520.dp)) {
            when (tab) {
                0 -> if (nav.chapters.isEmpty()) Empty("Bu belgede başlık yok.") else {
                    val here = nav.chapterIndex(s.cursor)
                    LazyColumn { items(nav.chapters.size) { i ->
                        val c = nav.chapters[i]
                        PlaceRow(c.title, null, Modifier.padding(start = ((c.level - 1).coerceIn(0, 4) * 14).dp), bold = i == here,
                            onTap = { onMove(c.offset) }, onPlay = { onGo(c.offset, true) })
                    } }
                }
                1 -> if (doc.bookmarks.isEmpty()) Empty("Yer imi yok. Üst çubuktaki yer imi düğmesiyle eklenir.") else LazyColumn {
                    items(doc.bookmarks, key = { it.id }) { b ->
                        PlaceRow(b.excerpt.ifEmpty { "Yer imi" }, nav.chapterTitle(b.offset) + " · " + Format.date(b.createdAt, "d MMM"),
                            onTap = { onGo(b.offset, false) }, onPlay = { onGo(b.offset, true) }, onDelete = { app.removeBookmark(b.id) })
                    }
                }
                2 -> if (doc.highlights.isEmpty()) Empty("İşaret yok. Bir cümleye basılı tutup işaretle.") else LazyColumn {
                    items(doc.highlights.sortedBy { it.location }, key = { it.id }) { h ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.width(4.dp).height(36.dp).background(Color(h.color.argb)))
                            PlaceRow(h.text, listOfNotNull(nav.chapterTitle(h.location), h.note).joinToString(" · "), Modifier.weight(1f),
                                onTap = { onGo(h.location, false) }, onPlay = { onGo(h.location, true) }, onDelete = { app.removeHighlight(h.id) })
                        }
                    }
                }
                else -> {
                    val mine = notes.filter { it.doc == doc.id }.sortedBy { it.location }
                    if (mine.isEmpty()) Empty("Not yok. Mikrofon düğmesiyle sesli not, seçim menüsüyle yazılı not eklenir.")
                    else LazyColumn {
                        items(mine, key = { it.id }) { n ->
                            PlaceRow((if (n.hasVoice) "🎙 " else "") + n.text.ifEmpty { "Sesli not · ${Format.clock(n.seconds ?: 0.0)}" }, n.quote,
                                onTap = { onGo(n.location, false) }, onPlay = { onGo(n.location, true) }, onDelete = { app.notes.delete(n.id) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Empty(t: String) = Text(t, Modifier.padding(vertical = 24.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))

@Composable
private fun PlaceRow(title: String, sub: String?, modifier: Modifier = Modifier, bold: Boolean = false, onTap: () -> Unit, onPlay: () -> Unit, onDelete: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().clickable(onClick = onTap).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(start = 8.dp)) {
            Text(title, maxLines = 3, overflow = TextOverflow.Ellipsis, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal)
            if (!sub.isNullOrBlank()) Text(sub, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        onDelete?.let { IconButton(onClick = it) { Icon(Icons.Default.Delete, "Sil", tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)) } }
        IconButton(onClick = onPlay) { Icon(Icons.Default.PlayArrow, "Buradan oku", tint = MaterialTheme.colorScheme.primary) }
    }
}

// MARK: - search inside the document

@Composable
fun SearchSheet(app: AppModel, onDismiss: () -> Unit, onHit: (Int) -> Unit) {
    val nav = app.player.nav
    var query by remember { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<IntRange>>(emptyList()) }
    LaunchedEffect(query) {
        kotlinx.coroutines.delay(250)
        hits = withContext(Dispatchers.Default) { TextFold.findAll(nav.text, query, 300) }
    }
    Sheet(onDismiss) {
        Text("Belgede ara", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(vertical = 8.dp), singleLine = true, placeholder = { Text("Kelime ya da ifade") })
        if (query.isNotBlank()) Text("${hits.size}${if (hits.size >= 300) "+" else ""} sonuç", style = MaterialTheme.typography.labelMedium)
        LazyColumn(Modifier.heightIn(max = 480.dp)) {
            items(hits) { r ->
                val a = maxOf(0, r.first - 50)
                val b = minOf(nav.length, r.last + 60)
                Column(Modifier.fillMaxWidth().clickable { onHit(r.first) }.padding(vertical = 8.dp)) {
                    Text(buildAnnotatedString {
                        append(if (a > 0) "…" else "")
                        append(nav.text.substring(a, r.first).replace('\n', ' '))
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold, background = Color(HighlightColor.YELLOW.argb).copy(alpha = 0.5f))) { append(nav.text.substring(r.first, r.last + 1)) }
                        append(nav.text.substring(r.last + 1, b).replace('\n', ' '))
                        append("…")
                    }, maxLines = 3)
                    nav.chapterTitle(r.first)?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary) }
                }
                HorizontalDivider()
            }
        }
    }
}

// MARK: - speed

@Composable
fun SpeedSheet(app: AppModel, onDismiss: () -> Unit) {
    val s by app.player.state.collectAsState()
    var documentOnly by remember { mutableStateOf(app.currentDocument?.speed != null) }
    Sheet(onDismiss) {
        Text("Hız", style = MaterialTheme.typography.titleLarge)
        Text("${"%.2f".format(s.speed)}× · yaklaşık ${Format.wpm(app.player.charsPerSecond, s.speed)} kelime/dk", color = MaterialTheme.colorScheme.primary)
        Slider(s.speed.toFloat(), { app.setSpeed(it.toDouble(), documentOnly) }, valueRange = 0.5f..3.5f, steps = 59)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5).forEach { v ->
                FilterChip(selected = kotlin.math.abs(s.speed - v) < 0.01, onClick = { app.setSpeed(v, documentOnly) }, label = { Text("$v".trimEnd('0').trimEnd('.') + "×") })
            }
        }
        SwitchRow("Yalnız bu belge için", documentOnly) { documentOnly = it; app.setSpeed(s.speed, it) }
    }
}

// MARK: - Ses Ayarları

@Composable
fun AudioSettingsSheet(app: AppModel, nav: NavHostController, onDismiss: () -> Unit) {
    Sheet(onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text("Ses Ayarları", style = MaterialTheme.typography.titleLarge)
            AudioSettingsContent(app, onCloud = { onDismiss(); nav.navigate(Routes.CLOUD) })
        }
    }
}

@Composable
fun AudioSettingsContent(app: AppModel, onCloud: () -> Unit) {
    val context = LocalContext.current
    val s = app.settings
    val ps by app.player.state.collectAsState()
    val doc = app.currentDocument
    var voices by remember { mutableStateOf<List<VoiceInfo>>(emptyList()) }
    var engines by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    LaunchedEffect(s.ttsEngine) {
        repeat(20) {
            val b = app.player.ttsBackend()
            if (b.ready) { voices = b.voices() + VoiceCatalog.extra(); engines = b.engines(); return@LaunchedEffect }
            kotlinx.coroutines.delay(250)
        }
        voices = VoiceCatalog.extra()
    }
    val docLang = doc?.language?.take(2) ?: "tr"
    var lang by remember { mutableStateOf(docLang) }
    var documentOnly by remember { mutableStateOf(doc?.voiceID != null) }

    SectionLabel("Hız")
    Text("${"%.2f".format(ps.speed)}× · yaklaşık ${Format.wpm(app.player.charsPerSecond, ps.speed)} kelime/dk")
    Slider(ps.speed.toFloat(), { app.setSpeed(it.toDouble(), doc?.speed != null) }, valueRange = 0.5f..3.5f, steps = 59)

    SectionLabel("Ses")
    ChoiceRow(listOf("tr", "en", "de", "fr", "ar").distinct(), lang, { java.util.Locale(it).getDisplayLanguage(Format.tr).replaceFirstChar { c -> c.titlecase(Format.tr) } }) { lang = it }
    val current = if (lang == docLang && doc?.voiceID != null) doc.voiceID else s.voiceByLanguage[lang]
    val forLang = voices.filter { it.language == lang || (lang == "tr" && it.language == "tur") || (lang == "en" && it.language == "eng") }
    if (doc != null) SwitchRow("Yalnız bu belge için", documentOnly) { documentOnly = it }
    if (forLang.isEmpty()) Text("Bu dil için ses bulunamadı. Android ayarlarından ses verisini indirin.", style = MaterialTheme.typography.bodySmall)
    Column(Modifier.heightIn(max = 260.dp).verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().clickable { app.setVoice("", lang, false); s.voiceByLanguage = s.voiceByLanguage - lang }.padding(vertical = 8.dp)) {
            Text((if (current.isNullOrEmpty()) "✓ " else "") + "Dilin varsayılan sesi")
        }
        forLang.forEach { v ->
            Row(Modifier.fillMaxWidth().clickable { app.setVoice(v.id, lang, documentOnly && lang == docLang) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text((if (v.id == current) "✓ " else "") + v.name, fontWeight = if (v.id == current) FontWeight.SemiBold else FontWeight.Normal)
                    Text(listOfNotNull(v.locale, if (v.quality >= 400) "yüksek kalite" else null, if (!v.installed) "kurulu değil" else null).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
                if (!v.id.startsWith("eleven:") && !v.id.startsWith("cloud:")) TextButton(onClick = {
                    val t = s.tune(v.id)
                    app.player.ttsBackend().preview(v, ps.speed.toFloat(), t.pitch.toFloat())
                }) { Text("Dinle") }
            }
        }
    }
    current?.takeIf { it.isNotEmpty() }?.let { vid ->
        SectionLabel("Bu sesin ayarı")
        val t = s.tune(vid)
        SliderRow("Kalınlık", t.pitch, 0.5..2.0, shown = { "${(it * 100).toInt()}" }) { s.setTune(vid, t.copy(pitch = it)); app.applyAudioSettings() }
        SliderRow("Ses miktarı", t.volume, 0.0..1.0, shown = { "${(it * 100).toInt()}" }) { s.setTune(vid, t.copy(volume = it)); app.applyAudioSettings() }
        TextButton(onClick = { s.voiceTune = s.voiceTune - vid; app.applyAudioSettings() }) { Text("Sesin kendi ayarına dön") }
    }
    TextButton(onClick = onCloud) { Text("Bulut sesleri (ElevenLabs, OpenAI, Google, Azure)…") }
    if (engines.size > 1) {
        SectionLabel("Ses motoru")
        ChoiceRow(listOf("") + engines.map { it.first }, s.ttsEngine, { k -> if (k.isEmpty()) "Sistem varsayılanı" else engines.first { it.first == k }.second }) {
            s.ttsEngine = it; app.player.setEngine(it)
        }
    }
    TextButton(onClick = {
        runCatching { context.startActivity(Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }) { Text("Android metin okuma ayarları (ses indir)…") }

    SectionLabel("Okuma")
    SwitchRow("Cümle başından başla", s.startAtSentence) { s.startAtSentence = it; app.applyAudioSettings() }
    SwitchRow("Karışık dil", s.mixedLanguage, "Türkçe metindeki İngilizce cümleleri İngilizce sesle okur (ve tersi).") { s.mixedLanguage = it; app.applyAudioSettings() }
    SwitchRow("Web ve e-posta adreslerini sadeleştir", s.simplifyLinks) { s.simplifyLinks = it; app.applyAudioSettings() }
    SwitchRow("Kaynak göstermelerini atla", s.skipCitations, "[12], (Kant, 1781) sayfada kalır, sesle okunmaz.") { s.skipCitations = it; app.applyAudioSettings() }
    Text("Belge bitince", Modifier.padding(top = 8.dp))
    ChoiceRow(EndBehavior.entries, s.endBehavior, { it.label }) { s.endBehavior = it }

    SectionLabel("Müzik")
    ChoiceRow(MusicMix.shown, if (s.musicMix == MusicMix.off) MusicMix.off else MusicMix.mix, { it.label }) { s.musicMix = it; app.applyAudioSettings() }
    SwitchRow("Müzik arası", s.musicBreak, "Belirli dinleme süresinde bir ses durur, müzik duyulur.") { s.musicBreak = it; app.applyAudioSettings() }
    if (s.musicBreak) {
        SliderRow("Her", s.breakMinutes, 3.0..15.0, steps = 11, shown = { "${it.toInt()} dk" }) { s.breakMinutes = it.toInt().toDouble(); app.applyAudioSettings() }
        SliderRow("Ara", s.breakSeconds, 30.0..120.0, steps = 8, shown = { "${it.toInt()} sn" }) { s.breakSeconds = (it / 10).toInt() * 10.0; app.applyAudioSettings() }
    }
    SwitchRow("Aktif bekleme", s.remotePauseWaits, "Kulaklığın ⏯ tuşu okumayı bekletir, sonra kendiliğinden sürer.") { s.remotePauseWaits = it }
    if (s.remotePauseWaits) SliderRow("Bekleme", s.waitSeconds, 0.0..300.0, steps = 9, shown = { if (it < 1) "müzik bitene dek" else "${it.toInt()} sn" }) {
        s.waitSeconds = (it / 30).toInt() * 30.0
    }
}

// MARK: - Görsel Ayarlar

@Composable
fun VisualSettingsSheet(app: AppModel, onDismiss: () -> Unit) {
    Sheet(onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text("Görsel Ayarlar", style = MaterialTheme.typography.titleLarge)
            VisualSettingsContent(app.settings)
        }
    }
}

@Composable
fun VisualSettingsContent(s: Settings) {
    SectionLabel("Yazı")
    ChoiceRow(ReaderFont.entries, s.font, { it.label }) { s.font = it }
    SliderRow("Boyut", s.fontSize, 12.0..40.0, shown = { "${it.toInt()}" }) { s.fontSize = it.toInt().toDouble() }
    SliderRow("Satır aralığı", s.lineSpacing, 0.0..20.0, shown = { "${it.toInt()}" }) { s.lineSpacing = it.toInt().toDouble() }
    SliderRow("Harf aralığı", s.characterSpacing, -2.0..6.0, shown = { "%.1f".format(it) }) { s.characterSpacing = it }

    SectionLabel("Tema")
    SwitchRow("Telefonun açık/koyu ayarını izle", s.followSystem) { s.followSystem = it }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ReaderTheme.entries.forEach { t ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { s.theme = t; s.followSystem = false }) {
                Box(Modifier.size(52.dp).background(t.background, RoundedCornerShape(10.dp))
                    .border(if (s.theme == t && !s.followSystem) 3.dp else 1.dp, if (s.theme == t) MaterialTheme.colorScheme.primary else t.hairline, RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center) { Text("Aa", color = t.text, fontFamily = FontFamily.Serif) }
                Text(t.label, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
    SectionLabel("Renk")
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Settings.accents.forEach { (name, hex) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { s.accentHex = hex }) {
                Box(Modifier.size(34.dp).background(Settings.parseHex(hex)!!, CircleShape)
                    .border(if (s.accentHex.equals(hex, true)) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape))
                Text(name, style = MaterialTheme.typography.labelSmall)
            }
        }
    }

    SectionLabel("Okunan kelime ve cümle")
    SwitchRow("Okunan kelimeyi işaretle", s.showSpokenWord) { s.showSpokenWord = it }
    if (s.showSpokenWord) ColorChoices(MarkColor.entries.filter { it != MarkColor.paper }, s.wordColor) { s.wordColor = it }
    SwitchRow("Okunan cümleyi işaretle", s.showSpokenLine) { s.showSpokenLine = it }
    if (s.showSpokenLine) ColorChoices(MarkColor.entries, s.lineColor) { s.lineColor = it }

    SectionLabel("Konuşma imleci")
    ChoiceRow(CursorPosition.entries, s.cursorPosition, { it.label }) { s.cursorPosition = it }
    SwitchRow("Odak kipi", s.focusMode, "Okunan cümle dışındaki metin soluklaşır.") { s.focusMode = it }
    Text("Sayfa karartma", Modifier.padding(top = 8.dp))
    ChoiceRow(PageDim.entries, s.pageDim, { it.label }) { s.pageDim = it }
    Text(s.pageDim.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
    if (s.pageDim != PageDim.off) SliderRow("Güç", s.pageDimStrength, 0.15..0.85, shown = { "%${(it * 100).toInt()}" }) { s.pageDimStrength = it }
    TextButton(onClick = { s.restoreVisualDefaults() }) { Text("Varsayılan görünüme dön") }
}

@Composable
private fun ColorChoices(colors: List<MarkColor>, selected: MarkColor, onPick: (MarkColor) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        colors.forEach { c ->
            Box(Modifier.size(30.dp).background(c.color, CircleShape)
                .border(if (c == selected) 3.dp else 1.dp, if (c == selected) MaterialTheme.colorScheme.primary else Color.Gray, CircleShape)
                .clickable { onPick(c) })
        }
    }
}

// MARK: - the selection menu (a long press on a sentence)

@Composable
fun SelectionSheet(app: AppModel, nav: NavHostController, doc: DocumentRecord, range: IntRange, onChange: (IntRange) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val tn = app.player.nav
    val text = tn.substring(range).trim()
    val existing = doc.highlights.filter { it.location < range.last + 1 && range.first < it.end }
    var noteMode by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf(existing.firstOrNull()?.note ?: "") }
    Sheet(onDismiss) {
        Text("“$text”", Modifier.heightIn(max = 160.dp).verticalScroll(rememberScrollState()), fontFamily = FontFamily.Serif)
        Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            TextButton(onClick = { tn.sentenceBefore(range.first)?.let { onChange(it.first..range.last) } }) { Text("← Önceki cümleyi kat") }
            TextButton(onClick = { tn.sentenceEnd(range.last + 1)?.let { e -> tn.sentenceRange(e)?.let { onChange(range.first..it.last) } } }) { Text("Sonrakini kat →") }
        }
        if (noteMode) {
            OutlinedTextField(note, { note = it }, Modifier.fillMaxWidth(), label = { Text("Not") }, minLines = 3)
            Row {
                TextButton(onClick = { noteMode = false }) { Text("Vazgeç") }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = {
                    val h = existing.firstOrNull()
                    if (h != null) app.setHighlightNote(h.id, note) else { app.addHighlight(range, HighlightColor.YELLOW, text, note) }
                    onDismiss()
                }) { Text("Kaydet") }
            }
            return@Sheet
        }
        Action("Buradan oku") { app.player.moveCursor(range.first, play = true); onDismiss() }
        Text("İşaretle", Modifier.padding(top = 8.dp), style = MaterialTheme.typography.labelLarge)
        Row(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            HighlightColor.entries.forEach { c ->
                Box(Modifier.size(36.dp).background(Color(c.argb), CircleShape).clickable { app.addHighlight(range, c, text); onDismiss() })
            }
        }
        if (existing.isNotEmpty()) Action("İşareti kaldır") { existing.forEach { app.removeHighlight(it.id) }; onDismiss() }
        Action(if (existing.any { it.note != null }) "Notu düzenle" else "Not ekle") { noteMode = true }
        Action("Sesli not") { onDismiss(); app.startVoiceNote(range) }
        Action("Yer imi") { app.addBookmark(range.first); onDismiss() }
        Action("Kopyala") {
            context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Wise Path", text)); onDismiss()
        }
        Action("Paylaş") {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "“$text”\n— ${doc.title}${doc.author?.let { ", $it" } ?: ""}"), "Paylaş"))
            onDismiss()
        }
        Action("Genişlet (istem oluştur)") { onDismiss(); nav.navigate(Routes.expand(doc.id, range.first, range.last + 1)) }
    }
}

@Composable
private fun Action(t: String, onClick: () -> Unit) {
    Text(t, Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp), color = MaterialTheme.colorScheme.primary)
    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
}

@Suppress("unused") private val unusedTune = VoiceTune()
@Suppress("unused") private val unusedIcon = Icons.Default.Bookmark
