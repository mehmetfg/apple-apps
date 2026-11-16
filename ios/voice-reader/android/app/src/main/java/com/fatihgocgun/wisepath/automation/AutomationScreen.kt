// Otomasyon (port of Views/AutomationViews.swift and the automation question of FinishedViews.swift): the list of
// automations and the editor of one, the library card (start, go on from where it was left, stop), the line the
// mini player shows while one runs, and the question asked when a step's book is finished.
package com.fatihgocgun.wisepath.automation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.ui.Page
import com.fatihgocgun.wisepath.ui.Palette
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
private fun runner(): AutomationRunner = AutomationRunner.get(AppModel.get(LocalContext.current))

private val Orange = Color(0xFFFF9500)

/** A tint per folder, stable across launches (the iOS folder colours are not ported). */
private fun folderTint(folder: String?): Color {
    val tints = listOf(Color(0xFF3A7BD5), Color(0xFF2E9E6A), Color(0xFFD9822B), Color(0xFF8E5CC4), Color(0xFFC94F6D), Color(0xFF2A9DB0))
    return if (folder == null) Color.Gray else tints[Math.floorMod(folder.hashCode(), tints.size)]
}

// MARK: - the list

/** The list of automations and the editor of one. */
@Composable
fun AutomationScreen(onBack: () -> Unit) {
    val r = runner()
    val app = AppModel.get(LocalContext.current)
    var editing by remember { mutableStateOf<Automation?>(null) }
    var choosing by remember { mutableStateOf<Automation?>(null) }
    editing?.let { a ->
        AutomationEditor(a, onCancel = { editing = null }, onSave = { r.store.upsert(it); editing = null })
        return
    }
    Page("Otomasyon", onBack) { pad ->
        LazyColumn(Modifier.fillMaxSize().padding(pad), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (r.run != null) {
                item { Text("Şu an", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f)) }
                item { AutomationNowCard() }
            }
            itemsIndexed(r.store.list, key = { _, a -> a.id }) { i, a ->
                AutomationRow(a, i, running = r.run?.automation?.id == a.id,
                    start = { if (r.store.resumePoint(a) != null) choosing = a else r.start(a) },
                    edit = { editing = a })
            }
            item {
                TextButton(onClick = {
                    editing = Automation(name = "Yeni otomasyon", steps = listOf(AutomationStep.read(app.store.folders.value.firstOrNull() ?: "Felsefe", 15)))
                }) { Icon(Icons.Default.Add, null); Spacer(Modifier.width(6.dp)); Text("Yeni otomasyon") }
            }
            item {
                Text("Her okuma adımı klasörün güncel kitabını (en son dinlediğin, bitmemiş olanı) kaldığı yerden okur; süre yalnız ses duyulurken sayılır. Süre dolunca cümlenin sonunda durur, ara ve sıradaki adım kendiliğinden gelir; telefona dokunman gerekmez. Durdurursan ya da başka bir kitap açarsan otomasyon kaldığı adımı hatırlar: Kütüphane'deki Otomasyon kartından ya da burada ▶ ile kaldığı yerden sürdürürsün. Baştan, ilk adımdan tam sürelerle başlar; kitaplar yine kaldıkları yerden okunur.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
            }
        }
    }
    choosing?.let { a ->
        val p = r.store.resumePoint(a)
        AlertDialog(
            onDismissRequest = { choosing = null },
            title = { Text(a.name) },
            text = {
                Column {
                    if (p != null) {
                        val s = a.steps[p.step]
                        TextButton(onClick = { choosing = null; r.start(a, resume = true) }) {
                            Text("Kaldığı yerden · ${s.folder ?: ""} · ${AutoFormat.clock(maxOf(0, s.seconds - p.listened.roundToInt()))} kaldı")
                        }
                    }
                    TextButton(onClick = { choosing = null; r.start(a) }) { Text("Baştan başlat") }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { choosing = null }) { Text("Vazgeç") } },
        )
    }
}

@Composable
private fun AutomationRow(a: Automation, index: Int, running: Boolean, start: () -> Unit, edit: () -> Unit) {
    val r = runner()
    val resume = if (running) null else r.store.resumePoint(a)
    var menu by remember { mutableStateOf(false) }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).clickable(onClick = edit), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(a.name, fontWeight = FontWeight.SemiBold)
                Text(a.steps.joinToString(" → ") { if (it.kind == StepKind.read) "${it.folder ?: "?"} ${it.seconds / 60}" else "ara" },
                    style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                Text("Okuma ${AutoFormat.minutes(a.readingSeconds)} · toplam ${AutoFormat.minutes(a.totalSeconds)}",
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f))
                if (resume != null) {
                    val s = a.steps[resume.step]
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Bookmark, null, Modifier.size(12.dp), tint = Palette.play)
                        Spacer(Modifier.width(4.dp))
                        Text("Kaldığı yer: ${resume.step + 1}/${a.steps.size} · ${s.folder ?: ""} · ${AutoFormat.clock(maxOf(0, s.seconds - resume.listened.roundToInt()))} kaldı",
                            style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = Palette.play)
                    }
                }
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Diğer") }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(text = { Text("Düzenle") }, onClick = { menu = false; edit() })
                    DropdownMenuItem(text = { Text("Yukarı taşı") }, onClick = { menu = false; r.store.move(index, -1) })
                    DropdownMenuItem(text = { Text("Aşağı taşı") }, onClick = { menu = false; r.store.move(index, 1) })
                    DropdownMenuItem(text = { Text("Sil") }, onClick = {
                        menu = false
                        if (running) r.stopAutomation()
                        r.store.delete(listOf(a.id))
                    })
                }
            }
            IconButton(
                onClick = { if (running) r.stopAutomation() else start() },
                modifier = Modifier.size(40.dp).clip(CircleShape).background(if (running) Color.Gray else Palette.play),
            ) {
                Icon(if (running) Icons.Default.Stop else Icons.Default.PlayArrow,
                    if (running) "Otomasyonu durdur" else "Otomasyonu başlat: ${a.name}", tint = Color.White)
            }
        }
    }
}

/** The running automation: step, book, time left, stop. */
@Composable
fun AutomationNowCard() {
    val r = runner()
    val run = r.run ?: return
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            run.automation.steps.forEachIndexed { i, s ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        when { i < run.step -> Icons.Default.CheckCircle; i == run.step -> Icons.Default.PlayCircle; else -> Icons.Default.RadioButtonUnchecked },
                        null, tint = if (i == run.step) Palette.play else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    )
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(s.title, style = MaterialTheme.typography.bodyMedium, fontWeight = if (i == run.step) FontWeight.SemiBold else FontWeight.Normal)
                        if (s.kind == StepKind.read && s.folder != null) {
                            val doc = if (i == run.step) run.documentTitle else r.automationDocument(s.folder)?.title
                            Text(doc ?: "Okunacak kitap yok", style = MaterialTheme.typography.bodySmall, maxLines = 1,
                                overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        }
                    }
                    if (i == run.step) AutomationClock()
                }
            }
            OutlinedButton(onClick = { r.stopAutomation() }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Stop, null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(6.dp))
                Text("Durdur", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

/** Time left in the current step (reading: listening time left; pause: the countdown). */
@Composable
fun AutomationClock() {
    val r = runner()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val run = r.run ?: return
    val text = when (run.phase) {
        Phase.thinking -> AutoFormat.clock(maxOf(0, (((run.phaseEnds ?: now) - now) / 1000.0).roundToInt()))
        Phase.reading -> AutoFormat.clock(maxOf(0, (run.stepSeconds - run.listenedBefore - r.segmentListened).roundToInt())) + " kaldı"
        Phase.announcing -> "duyuru"
    }
    Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
}

/** Under the title in the mini player while an automation runs (iOS AutomationBadge). Nothing when none runs. */
@Composable
fun AutomationStatusLine() {
    val r = runner()
    val run = r.run ?: return
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Icon(if (run.phase == Phase.thinking) Icons.Default.Psychology else Icons.AutoMirrored.Filled.ListAlt, null,
            Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Text("${run.position} · ${run.stepTitle}", style = MaterialTheme.typography.labelMedium, maxLines = 1,
            overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        AutomationClock()
    }
}

// MARK: - the library card

/** The automation's steps as one strip: a reading step is a bar as long as its minutes; a break is a dot. */
@Composable
fun AutomationTrack(a: Automation, current: Int?, heard: Double = 0.0, modifier: Modifier = Modifier) {
    val total = maxOf(1, a.readingSeconds).toFloat()
    Row(modifier.fillMaxWidth().height(8.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        a.steps.forEachIndexed { i, s ->
            val f = when {
                current == null -> 0.0
                i < current -> 1.0
                i > current -> 0.0
                s.kind == StepKind.pause -> 1.0
                else -> minOf(1.0, heard / maxOf(1, s.seconds))
            }
            if (s.kind == StepKind.read) {
                val tint = folderTint(s.folder)
                Box(Modifier.weight(maxOf(0.01f, s.seconds / total)).fillMaxHeight().clip(RoundedCornerShape(4.dp)).background(tint.copy(alpha = 0.22f))) {
                    if (f > 0) Box(Modifier.fillMaxWidth(f.toFloat()).fillMaxHeight().clip(RoundedCornerShape(4.dp)).background(tint))
                }
            } else {
                Box(Modifier.size(7.dp).clip(CircleShape).background(Color.Gray.copy(alpha = if (f > 0) 0.8f else 0.25f)))
            }
        }
    }
}

/** The library home's card: start / go on / stop the automation, which step and book. */
@Composable
fun AutomationCard(onOpen: () -> Unit) {
    val r = runner()
    val run = r.run
    val a = run?.automation ?: r.store.featured ?: return
    val resume = if (run == null) r.store.resumePoint(a) else null
    var menu by remember { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.AutoMirrored.Filled.ListAlt, null, tint = if (run != null) Orange else MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text(a.name, Modifier.weight(1f).clickable(onClick = onOpen), fontWeight = FontWeight.SemiBold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, color = if (run != null) Orange else MaterialTheme.colorScheme.onSurface)
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Otomasyon") }
                    DropdownMenu(menu, { menu = false }) {
                        if (run != null) {
                            DropdownMenuItem(text = { Text("Durdur · ${a.name}") }, onClick = { menu = false; r.stopAutomation() })
                        } else if (resume != null) {
                            DropdownMenuItem(text = { Text("Kaldığı yerden · ${a.name}") }, onClick = { menu = false; r.start(a, resume = true) })
                            DropdownMenuItem(text = { Text("Baştan") }, onClick = { menu = false; r.start(a) })
                        } else {
                            DropdownMenuItem(text = { Text("Başlat · ${a.name}") }, onClick = { menu = false; r.start(a) })
                        }
                        DropdownMenuItem(text = { Text("Bütün otomasyonlar") }, onClick = { menu = false; onOpen() })
                    }
                }
                IconButton(
                    onClick = { if (run != null) r.stopAutomation() else r.start(a, resume = resume != null) },
                    modifier = Modifier.size(36.dp).clip(CircleShape).background(if (run != null) Color.Gray else Palette.play),
                ) {
                    Icon(if (run != null) Icons.Default.Stop else Icons.Default.PlayArrow,
                        if (run != null) "Otomasyonu durdur" else "Otomasyonu başlat", tint = Color.White)
                }
            }
            val step = run?.step ?: resume?.step
            val heard = if (run != null) run.listenedBefore + (if (run.phase == Phase.reading) r.segmentListened else 0.0) else resume?.listened ?: 0.0
            AutomationTrack(a, step, heard)
            if (step != null) CardStatus(a, step, running = run != null, listened = heard)
        }
    }
}

/** Under the strip: which step, which book, how much is left in it. */
@Composable
private fun CardStatus(a: Automation, step: Int, running: Boolean, listened: Double) {
    val r = runner()
    val s = a.steps.getOrNull(step) ?: return
    val run = r.run
    val book = if (running && run?.phase != Phase.thinking) run?.documentTitle else s.folder?.let { r.automationDocument(it)?.title }
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (running) "Şimdi" else "Kaldığı yer", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = if (running) Palette.play else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            Text(" · ${step + 1}/${a.steps.size} · ${if (running) run?.stepTitle ?: "" else s.folder ?: ""}",
                Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (running) AutomationClock()
            else Text(AutoFormat.clock(maxOf(0, s.seconds - listened.roundToInt())) + " kaldı", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        if (book != null) Text(book, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
    }
}

// MARK: - the editor

@Composable
private fun AutomationEditor(initial: Automation, onCancel: () -> Unit, onSave: (Automation) -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val r = runner()
    val folders by app.store.folders.collectAsState()
    var a by remember { mutableStateOf(initial) }
    var addMenu by remember { mutableStateOf(false) }
    fun setStep(i: Int, s: AutomationStep) { a = a.copy(steps = a.steps.toMutableList().also { it[i] = s }) }
    Page(a.name, onCancel, actions = {
        TextButton(onClick = { onSave(a) }, enabled = a.steps.isNotEmpty()) { Text("Kaydet") }
    }) { pad ->
        LazyColumn(Modifier.fillMaxSize().padding(pad), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { OutlinedTextField(a.name, { a = a.copy(name = it) }, label = { Text("Ad") }, singleLine = true, modifier = Modifier.fillMaxWidth()) }
            item { Text("Adımlar", style = MaterialTheme.typography.labelLarge) }
            itemsIndexed(a.steps, key = { _, s -> s.id }) { i, s ->
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(if (s.kind == StepKind.read) Icons.AutoMirrored.Filled.MenuBook else Icons.Default.Psychology, null)
                            Spacer(Modifier.width(8.dp))
                            if (s.kind == StepKind.read) {
                                var pick by remember { mutableStateOf(false) }
                                Box(Modifier.weight(1f)) {
                                    TextButton(onClick = { pick = true }) { Text("Klasör: ${s.folder ?: "seçilmedi"}") }
                                    DropdownMenu(pick, { pick = false }) {
                                        folders.forEach { f -> DropdownMenuItem(text = { Text(f) }, onClick = { pick = false; setStep(i, s.copy(folder = f)) }) }
                                    }
                                }
                            } else Text("Düşünme arası: ${AutoFormat.clock(s.seconds)}", Modifier.weight(1f))
                            IconButton(onClick = { if (i > 0) a = a.copy(steps = a.steps.toMutableList().also { l -> l.add(i - 1, l.removeAt(i)) }) }) {
                                Icon(Icons.Default.ArrowUpward, "Yukarı")
                            }
                            IconButton(onClick = { if (i < a.steps.size - 1) a = a.copy(steps = a.steps.toMutableList().also { l -> l.add(i + 1, l.removeAt(i)) }) }) {
                                Icon(Icons.Default.ArrowDownward, "Aşağı")
                            }
                            IconButton(onClick = { a = a.copy(steps = a.steps.filterIndexed { k, _ -> k != i }) }) { Icon(Icons.Default.Delete, "Sil") }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (s.kind == StepKind.read) {
                                Text("Süre: ${s.seconds / 60} dk", Modifier.weight(1f))
                                IconButton(onClick = { setStep(i, s.copy(seconds = maxOf(1, s.seconds / 60 - 1) * 60)) }) { Icon(Icons.Default.Remove, "Azalt") }
                                IconButton(onClick = { setStep(i, s.copy(seconds = minOf(120, s.seconds / 60 + 1) * 60)) }) { Icon(Icons.Default.Add, "Artır") }
                            } else {
                                Spacer(Modifier.weight(1f))
                                IconButton(onClick = { setStep(i, s.copy(seconds = maxOf(15, s.seconds - 15))) }) { Icon(Icons.Default.Remove, "Azalt") }
                                IconButton(onClick = { setStep(i, s.copy(seconds = minOf(600, s.seconds + 15))) }) { Icon(Icons.Default.Add, "Artır") }
                            }
                        }
                        if (s.kind == StepKind.read && s.folder != null) {
                            val doc = r.automationDocument(s.folder)
                            Text(doc?.let { "Güncel kitap: ${it.title} · %${(it.progress * 100).toInt()}" } ?: "Bu klasörde okunacak kitap yok",
                                style = MaterialTheme.typography.bodySmall, maxLines = 2, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        }
                    }
                }
            }
            item {
                Row {
                    Box {
                        TextButton(onClick = { addMenu = true }) { Icon(Icons.AutoMirrored.Filled.MenuBook, null); Spacer(Modifier.width(6.dp)); Text("Okuma ekle") }
                        DropdownMenu(addMenu, { addMenu = false }) {
                            folders.forEach { f ->
                                DropdownMenuItem(text = { Text(f) }, onClick = { addMenu = false; a = a.copy(steps = a.steps + AutomationStep.read(f, 15)) })
                            }
                        }
                    }
                    TextButton(onClick = { a = a.copy(steps = a.steps + AutomationStep.pause(60)) }) {
                        Icon(Icons.Default.Psychology, null); Spacer(Modifier.width(6.dp)); Text("Ara ekle")
                    }
                }
            }
            item {
                HorizontalDivider()
                Text("Okuma ${AutoFormat.minutes(a.readingSeconds)} · toplam ${AutoFormat.minutes(a.totalSeconds)}.",
                    Modifier.padding(top = 8.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
            }
        }
    }
}

// MARK: - the question when a step's book is finished

/** Shown app-wide (AppDialogs) while an automation waits for the reader's choice. */
@Composable
fun AutomationChoiceDialog() {
    val r = runner()
    val c = r.choice ?: return
    AlertDialog(
        onDismissRequest = {},
        title = { Text(c.finishedTitle?.let { "Sıradaki kitap bitmiş: $it" } ?: "${c.folder} klasöründe bitmemiş kitap yok") },
        text = {
            Column {
                Text("Kulaklıkta: ⏭ sıradaki · ⏮ bu kitap")
                c.nextTitle?.let { TextButton(onClick = { r.answerChoice(1) }) { Text("Sıradakine geç: $it") } }
                c.currentTitle?.let { TextButton(onClick = { r.answerChoice(-1) }) { Text("Bu kitaptan sür: $it") } }
            }
        },
        confirmButton = {
            TextButton(onClick = { r.answerChoice(0) }) { Text("Otomasyonu durdur", color = MaterialTheme.colorScheme.error) }
        },
    )
}
