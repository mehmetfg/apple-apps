// Ses › Bulut sesleri (port of Views/ElevenViews.swift): ElevenLabs (key, voice, model, quality, credits, the cache)
// and Google / Azure / OpenAI (provider, key, voice, this month's free allowance). Two tabs on one page.
package com.fatihgocgun.wisepath.cloud

import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.ui.Page
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.NumberFormat
import java.util.Locale

private val trNumber = NumberFormat.getIntegerInstance(Locale("tr"))
private fun n(v: Int) = trNumber.format(v)

@Composable
fun CloudVoiceSettings(onBack: () -> Unit) {
    val context = LocalContext.current
    val app = remember { AppModel.get(context) }
    val cloud = remember { CloudVoices.get(app) }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Page("Bulut sesleri", onBack) { pad ->
        Column(Modifier.fillMaxSize().padding(pad)) {
            TabRow(selectedTabIndex = tab) {
                Tab(tab == 0, onClick = { tab = 0 }, text = { Text("ElevenLabs") })
                Tab(tab == 1, onClick = { tab = 1 }, text = { Text("Google · Azure · OpenAI") })
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
                cloud.problem?.let {
                    Text("Son sorun: $it", color = Color(0xFFE08A00), style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(vertical = 6.dp))
                }
                if (tab == 0) ElevenPage(cloud) else CloudPage(cloud)
                Spacer(Modifier.height(32.dp))
            }
        }
    }
}

// MARK: building blocks

@Composable
private fun Header(text: String) {
    Text(text.uppercase(Locale("tr")), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 6.dp))
}

@Composable
private fun Labeled(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label)
        Spacer(Modifier.width(12.dp))
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Choice(label: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label)
        Spacer(Modifier.width(12.dp))
        Text(value, color = MaterialTheme.colorScheme.primary)
    }
}

/** A list of options in a dialog (the iOS Picker). */
@Composable
private fun <T> PickDialog(title: String, options: List<T>, selected: (T) -> Boolean, label: (T) -> String, onPick: (T) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                items(options) { o ->
                    Row(Modifier.fillMaxWidth().clickable { onPick(o); onDismiss() }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected(o), onClick = { onPick(o); onDismiss() })
                        Text(label(o))
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Kapat") } },
    )
}

@Composable
private fun KeyField(label: String, onSave: (String) -> Unit) {
    var key by remember { mutableStateOf("") }
    OutlinedTextField(key, { key = it }, label = { Text(label) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrect = false))
    Button(onClick = { onSave(key); key = "" }, enabled = key.isNotBlank(), modifier = Modifier.padding(top = 6.dp)) { Text("Kaydet") }
}

@Composable
private fun SampleButton(enabled: Boolean, make: () -> Clip, onError: (String?) -> Unit) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    OutlinedButton(onClick = {
        busy = true
        scope.launch {
            try {
                val clip = withContext(Dispatchers.IO) { make() }
                CloudBackend.installed?.playSample(clip)
            } catch (e: Exception) { onError(e.message) }
            busy = false
        }
    }, enabled = enabled && !busy, modifier = Modifier.padding(top = 8.dp)) {
        Text("Sesi dinle")
        if (busy) { Spacer(Modifier.width(8.dp)); CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) }
    }
}

// MARK: ElevenLabs

@Composable
private fun ElevenPage(e: CloudVoices) {
    val scope = rememberCoroutineScope()
    val test: () -> Unit = { scope.launch(Dispatchers.IO) { e.testEleven() } }
    var pickVoice by remember { mutableStateOf(false) }
    var pickModel by remember { mutableStateOf(false) }
    var pickQuality by remember { mutableStateOf(false) }
    var pickLimit by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            e.refreshStatsBlocking()
            if (e.elevenHasKey && e.subscription == null) e.testEleven()
        }
    }

    Header("Hesap")
    if (e.elevenHasKey) {
        Labeled("Anahtar", "Bu cihazda kayıtlı")
        TextButton(onClick = { e.deleteElevenKey() }) { Text("Anahtarı sil", color = MaterialTheme.colorScheme.error) }
    } else {
        KeyField("API anahtarı (xi-api-key)") { e.saveElevenKey(it); test() }
    }
    OutlinedButton(onClick = test, enabled = e.elevenHasKey) { Text("Bağlantıyı dene") }
    e.elevenStatus?.let { Footer(it) }
    Footer("elevenlabs.io › Developers › API Keys. Anahtar yalnız bu cihazın uygulama ayarlarında durur; koda, vault'a ya da eşitleme klasörüne yazılmaz. Kotayı görmek için anahtarda User okuma izni açık olmalı.")

    e.subscription?.let { a ->
        Header("Kredi")
        Labeled("Paket", a.tier)
        Labeled("Kalan", "${n(a.left)} / ${n(a.limit)} karakter")
        LinearProgressIndicator(progress = { a.used.toFloat() / maxOf(a.limit, 1) }, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp))
        a.resets?.let { Labeled("Yenilenme", Format.date(it, "d MMM yyyy")) }
    }

    Header("Ses")
    if (e.elevenVoices.isEmpty()) {
        Labeled("Seçili", e.elevenVoiceName.ifEmpty { "—" })
        Footer("Sesleri görmek için Bağlantıyı dene'ye bas.")
    } else {
        Choice("Ses", e.elevenVoiceName.ifEmpty { "—" }) { pickVoice = true }
    }
    SampleButton(e.elevenReady, { e.synthesizeEleven(e.settings.elevenVoice, CloudVoices.SAMPLE, "tr") }) { e.elevenStatus = it }

    Header("Üretim")
    Choice("Model", e.elevenModel.label) { pickModel = true }
    Choice("Kayıt kalitesi", e.quality.label) { pickQuality = true }
    Footer("Hız telefonda ayarlanır (ses perdesi korunur); bu yüzden bir paragraf her hız için yeniden üretilmez. Model ya da kalite değişince paragraflar yeniden üretilir.")

    Header("Telefonda saklanan")
    Choice("Sınır", limitLabel(e.limitMB)) { pickLimit = true }
    val context = LocalContext.current
    e.stats?.let { s ->
        Labeled("Saklanan", "${s.paragraphs} paragraf · ${Formatter.formatShortFileSize(context, s.bytes)}")
        Labeled("Süre", Format.duration(s.seconds))
    }
    Labeled("Telefondan çalınan", "${n(e.cachedCharacters)} karakter")
    Labeled("Krediyle üretilen", "${n(e.networkCharacters)} karakter")
    TextButton(onClick = { scope.launch(Dispatchers.IO) { e.clearCacheBlocking() } }) {
        Text("Saklananları sil", color = MaterialTheme.colorScheme.error)
    }
    Footer("Sınır dolunca en uzun zamandır dinlenmeyen paragraflar silinir. Yedeğe girmez. Sınır bütün bulut sesleri için ortaktır.")

    if (pickVoice) PickDialog("Ses", e.elevenVoices, { it.id == e.settings.elevenVoice },
        { if (it.category.isEmpty()) it.name else "${it.name} · ${it.category}" }, { e.chooseEleven(it.id) }) { pickVoice = false }
    if (pickModel) PickDialog("Model", ElevenModel.entries, { it == e.elevenModel }, { it.label }, { e.setElevenModel(it) }) { pickModel = false }
    if (pickQuality) PickDialog("Kayıt kalitesi", ElevenQuality.entries, { it == e.quality }, { it.label }, { e.chooseQuality(it) }) { pickQuality = false }
    if (pickLimit) PickDialog("Sınır", listOf(200, 500, 1000, 2000, 5000), { it == e.limitMB }, { limitLabel(it) }, { e.setLimit(it) }) { pickLimit = false }
}

private fun limitLabel(mb: Int) = if (mb >= 1000) "${mb / 1000} GB" else "$mb MB"

// MARK: Google, Azure, OpenAI

@Composable
private fun CloudPage(c: CloudVoices) {
    val scope = rememberCoroutineScope()
    val test: () -> Unit = { scope.launch(Dispatchers.IO) { c.testCloud() } }
    var pickProvider by remember { mutableStateOf(false) }
    var pickVoice by remember { mutableStateOf(false) }
    val p = c.provider
    LaunchedEffect(p) { if (c.cloudHasKey && c.cloudVoices.isEmpty()) withContext(Dispatchers.IO) { c.testCloud() } }

    Header("Sağlayıcı")
    Choice("Sağlayıcı", p.label) { pickProvider = true }
    Footer(p.keyHelp)

    Header("Hesap")
    if (c.cloudHasKey) {
        Labeled("Anahtar", "Bu cihazda kayıtlı")
        TextButton(onClick = { c.deleteCloudKey() }) { Text("Anahtarı sil", color = MaterialTheme.colorScheme.error) }
    } else {
        KeyField("API anahtarı") { c.saveCloudKey(it); test() }
    }
    if (p == CloudProvider.azure) {
        OutlinedTextField(c.settings.azureRegion, { c.settings.azureRegion = it.trim() }, label = { Text("Bölge (örn. westeurope)") },
            singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
    }
    OutlinedButton(onClick = test, enabled = c.cloudHasKey, modifier = Modifier.padding(top = 6.dp)) { Text("Bağlantıyı dene") }
    c.cloudStatus?.let { Footer(it) }

    Header("Ses")
    if (c.cloudVoices.isEmpty()) Labeled("Seçili", c.voiceNameOf(p).ifEmpty { "—" })
    else Choice("Ses", c.voiceNameOf(p).ifEmpty { "—" }) { pickVoice = true }
    SampleButton(c.cloudReady(p), { c.synthesizeCloud(p, c.voiceOf(p), CloudVoices.SAMPLE, "tr") }) { c.cloudStatus = it }

    Header("Bu ayın kullanımı")
    val free = c.freeAllowance()
    Labeled("Bu ay", "${n(c.usedThisMonth)} karakter")
    if (free > 0) {
        Labeled("Ücretsiz", "${n(free)} karakter")
        LinearProgressIndicator(progress = { minOf(c.usedThisMonth, free).toFloat() / free }, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp))
        Labeled("Kalan dinleme", "≈ ${hours(maxOf(0, free - c.usedThisMonth))} (330 kelime/dk)")
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Ücretsiz kotada kal", Modifier.weight(1f))
        Switch(c.stayFree, { c.changeStayFree(it) })
    }
    Footer("Açıkken ücretsiz kota dolunca paragrafları telefonun kendi sesi okur; hiçbir şey ücretlendirilmez. Sayaç bu telefonda gönderilen karakterleri sayar; asıl fatura sağlayıcının panelindedir. Telefonda saklanan paragraflar sayılmaz.")
    Footer("Google'da ayda 1–4 milyon, Azure'da 500 bin karakter ücretsiz: yüksek hızda ayda onlarca saat. Her paragraf bir kez üretilip telefonda saklanır.")

    if (pickProvider) PickDialog("Sağlayıcı", CloudProvider.entries, { it == p }, { it.label }, { c.setProvider(it) }) { pickProvider = false }
    if (pickVoice) PickDialog("Ses", c.cloudVoices, { it.id == c.voiceOf(p) }, { "${it.name} · ${it.detail}" }, { c.chooseCloud(it.id) }) { pickVoice = false }
}

/** Characters → listening time at 330 words a minute (≈ 7 characters a word with the space). */
private fun hours(chars: Int): String {
    val minutes = chars / (330.0 * 7)
    return if (minutes >= 60) "%.0f saat".format(minutes / 60) else "%.0f dk".format(minutes)
}

