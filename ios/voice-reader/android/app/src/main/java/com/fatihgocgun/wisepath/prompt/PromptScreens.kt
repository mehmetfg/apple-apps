// İstem oluşturucu (port of Views/PromptBuilder.swift) and Genişlet (Views/ExpandPrompt.swift): write the topic (or
// take a passage, the marks or a chapter of a book), copy the prompt, paste it into any AI, copy its answer back, and
// one tap adds it to the library.
package com.fatihgocgun.wisepath.prompt

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.PostAdd
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.ui.Page

// MARK: - shared bits

private fun copy(context: Context, text: String) {
    val cm = context.getSystemService(ClipboardManager::class.java)
    cm.setPrimaryClip(ClipData.newPlainText("Wise Path", text))
}

private fun clipboardText(context: Context): String? {
    val cm = context.getSystemService(ClipboardManager::class.java)
    return cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()?.takeIf { it.isNotBlank() }
}

private fun openUrl(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

@Composable
private fun Header(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 12.dp))
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
}

@Composable
private fun SwitchRow(label: String, on: Boolean, set: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { set(!on) }, verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(on, set)
    }
}

/** "İstemi kopyala", the two AI links and the prompt itself, folded. */
@Composable
private fun CopySection(prompt: String, enabled: Boolean, copied: Boolean, onCopied: () -> Unit) {
    val context = LocalContext.current
    var show by remember { mutableStateOf(false) }
    Button(onClick = { copy(context, prompt); onCopied() }, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
        Icon(if (copied) Icons.Default.Check else Icons.Default.ContentCopy, null)
        Spacer(Modifier.width(8.dp))
        Text(if (copied) "Kopyalandı" else "İstemi kopyala")
    }
    Row {
        TextButton(onClick = { openUrl(context, "https://claude.ai/new") }) { Text("Claude'u aç") }
        Spacer(Modifier.weight(1f))
        TextButton(onClick = { openUrl(context, "https://chatgpt.com/") }) { Text("ChatGPT'yi aç") }
    }
    TextButton(onClick = { show = !show }) { Text(if (show) "İstemi gizle" else "İstemi gör") }
    if (show) SelectionContainer {
        Text(prompt, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
    }
}

// MARK: - İstem oluşturucu

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PromptBuilderScreen(onBack: () -> Unit, onAdded: (String) -> Unit) {
    val context = LocalContext.current
    val app = AppModel.get(context)
    var req by remember { mutableStateOf(PromptRequest()) }
    var copied by remember { mutableStateOf(false) }
    fun set(r: PromptRequest) { req = r; copied = false }
    Page("İstem oluşturucu", onBack) { pad ->
        Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Header("1 · Konuyu yaz")
            OutlinedTextField(req.topic, { set(req.copy(topic = it)) }, Modifier.fillMaxWidth(), placeholder = { Text("Konu (örn. Leibniz'in monadları)") })
            OutlinedTextField(req.details, { set(req.copy(details = it)) }, Modifier.fillMaxWidth().heightIn(min = 80.dp),
                placeholder = { Text("Teknik ayrıntılar, kapsam, seviye (isteğe bağlı)") }, maxLines = 6)

            Header("Miktar ve biçim")
            Text("Biçim", style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PromptRequest.Form.entries.forEach { f -> FilterChip(req.form == f, { set(req.copy(form = f)) }, label = { Text(f.label) }) }
            }
            Text("Uzunluk", style = MaterialTheme.typography.bodyMedium)
            PromptRequest.Length.entries.forEach { l ->
                FilterChip(req.length == l, { set(req.copy(length = l)) }, label = { Text(l.label) })
            }
            SwitchRow("İngilizce yazılsın", req.english) { set(req.copy(english = it)) }

            Header("2 · Kopyala, yapay zekâya yapıştır")
            CopySection(req.prompt, enabled = req.topic.isNotBlank(), copied = copied) { copied = true }
            Footer("İstem herhangi bir yapay zekâda çalışır. Uygulamasını ya da sitesini aç, istemi yapıştır, gönder.")

            Header("3 · Cevabı kopyala, buraya dön")
            Button(onClick = {
                val text = clipboardText(context)
                if (text == null) app.message = "Panoda metin yok."
                else app.importText(text)?.let { onAdded(it.id) }
            }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.PostAdd, null); Spacer(Modifier.width(8.dp)); Text("Panodaki cevabı kitaplığa ekle")
            }
            Footer("Cevabın tamamını kopyala (çoğu uygulamada cevabın altındaki kopyala simgesi). Başlıklar içindekiler olur, metin dinlemeye hazır temizlenir. Cevabı .md dosyası olarak paylaşırsan \"Birlikte aç › Wise Path\" de aynı işi yapar.")
        }
    }
}

// MARK: - Genişlet

/** Genişlet: a prompt made from a book's passage (`start`/`end` offsets; both -1 = all of the book's marks). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpandPromptScreen(docId: String, start: Int, end: Int, onBack: () -> Unit, onAdded: (String) -> Unit) {
    val context = LocalContext.current
    val app = AppModel.get(context)
    val source = remember(docId, start, end) { ExpandSource.of(docId, start, end) }
    val doc = remember(docId) { app.store.document(docId) }
    var req by remember { mutableStateOf(ExpandRequest(purpose = ExpandRequest.Purpose.choices(source).first())) }
    var ctx by remember { mutableStateOf(ExpandRequest.Context()) }
    var copied by remember { mutableStateOf(false) }
    // the first half of a long answer, kept while the second is fetched (the app may go to the background meanwhile)
    val prefs = remember { context.getSharedPreferences("expand", Context.MODE_PRIVATE) }
    var part1 by remember { mutableStateOf(prefs.getString("expand.part1", "") ?: "") }
    var part1Source by remember { mutableStateOf(prefs.getString("expand.part1.source", "") ?: "") }
    fun keep(p: String, s: String) { part1 = p; part1Source = s; prefs.edit().putString("expand.part1", p).putString("expand.part1.source", s).apply() }
    fun set(r: ExpandRequest) { req = r; copied = false }

    LaunchedEffect(docId) {
        val d = doc ?: return@LaunchedEffect
        ctx = ExpandRequest.context(source, d, app.store.content(d.id))
    }
    val prompt = req.prompt(ctx, source)

    fun add(joining: Boolean) {
        var s = clipboardText(context) ?: run { app.message = "Panoda metin yok."; return }
        if (joining) {
            // the second answer may repeat the title: drop a first "# " line
            val trimmed = s.trimStart('\n')
            val first = trimmed.substringBefore('\n')
            val second = if (first.startsWith("# ")) trimmed.drop(first.length) else s
            s = part1 + "\n\n" + second
        }
        val d = doc ?: return
        val id = importExpansion(app, s, d) ?: return
        if (joining) keep("", "")
        onAdded(id)
    }

    val title = when (source) {
        is ExpandSource.Passage -> "Bu kısmı genişlet"
        is ExpandSource.Marks -> "İşaretlerimden metin"
        is ExpandSource.ChapterAt -> "Bölümden metin"
    }
    Page(title, onBack) { pad ->
        Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(when (source) {
                        is ExpandSource.Passage -> "SEÇİLİ KISIM"
                        is ExpandSource.Marks -> "${doc?.highlights?.size ?: 0} İŞARET"
                        is ExpandSource.ChapterAt -> "BÖLÜM"
                    }, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    Text(ctx.focus.ifEmpty { "…" }, fontFamily = FontFamily.Serif, maxLines = 6, overflow = TextOverflow.Ellipsis)
                    Text(listOfNotNull(ctx.book, ctx.chapter).filter { it.isNotEmpty() }.joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall, maxLines = 2, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
            }
            Footer(when (source) {
                is ExpandSource.Passage -> "İsteme kitabın adı, bölümü ve kısmın öncesindeki ve sonrasındaki paragraf da girer."
                is ExpandSource.Marks -> "İşaretler kitaptaki sırasıyla, bölüm başlıkları ve notlarınla isteme girer (en çok 60)."
                is ExpandSource.ChapterAt -> "Bölümün metni (en çok ≈ 4.000 kelime) isteme girer."
            })

            Header("1 · Ne için")
            ExpandRequest.Purpose.choices(source).chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { p ->
                        val on = req.purpose == p
                        Surface(
                            onClick = { set(req.copy(purpose = p)) },
                            modifier = Modifier.weight(1f).heightIn(min = 40.dp),
                            shape = RoundedCornerShape(10.dp),
                            color = if (on) MaterialTheme.colorScheme.primary.copy(alpha = 0.18f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                            border = if (on) BorderStroke(1.2.dp, MaterialTheme.colorScheme.primary) else null,
                        ) {
                            Text(p.label, Modifier.padding(10.dp), fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal)
                        }
                    }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            OutlinedTextField(req.note, { set(req.copy(note = it)) }, Modifier.fillMaxWidth(), placeholder = { Text("Ek isteğin (isteğe bağlı)") }, maxLines = 4)

            Header("2 · Uzunluk")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ExpandRequest.Length.entries.forEachIndexed { i, l ->
                    SegmentedButton(req.length == l, { set(req.copy(length = l)) }, SegmentedButtonDefaults.itemShape(i, ExpandRequest.Length.entries.size)) { Text(l.label) }
                }
            }
            Footer(req.length.detail + if (req.length == ExpandRequest.Length.long) " · gerekirse iki cevapta gelir" else "")
            SwitchRow("İngilizce yazılsın", req.english) { set(req.copy(english = it)) }

            Header("3 · Kopyala, yapay zekâya yapıştır")
            CopySection(prompt, enabled = ctx.focus.isNotEmpty(), copied = copied) { copied = true }

            Header("4 · Cevabı kopyala, buraya dön")
            if (part1.isEmpty() || part1Source != source.id) {
                Button(onClick = { add(false) }, Modifier.fillMaxWidth()) { Text("Panodaki cevabı kitaplığa ekle") }
                if (req.length == ExpandRequest.Length.long) {
                    TextButton(onClick = {
                        val s = clipboardText(context)
                        if (s == null) app.message = "Panoda metin yok." else keep(s, source.id)
                    }) { Text("Cevap yarım kaldı: 1. parçayı sakla") }
                }
            } else {
                Text("✓ 1. parça saklandı · ${part1.split(' ', '\n').count { it.isNotEmpty() }} kelime", color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                TextButton(onClick = { copy(context, "devam") }) { Text("\"devam\" yazısını kopyala") }
                Button(onClick = { add(true) }, Modifier.fillMaxWidth()) { Text("2. parçayı ekle ve kitaplığa koy") }
                TextButton(onClick = { keep("", "") }) { Text("Saklanan parçayı bırak", color = MaterialTheme.colorScheme.error) }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp), color = Color.Transparent)
            Footer("Metin \"${doc?.folder ?: "Klasörsüz"}\" içine \"Genişletme · …\" adıyla girer; yazar satırında kaynak kitap durur. Başlıklar içindekiler olur.")
        }
    }
}

/** An AI's answer to a Genişlet prompt, into the source book's folder; the new document's id, or null. */
private fun importExpansion(app: AppModel, raw: String, source: com.fatihgocgun.wisepath.model.DocumentRecord): String? {
    // the two-part marker never reaches the ear
    val text = raw.replace(Regex("(?m)^\\s*\\**DEVAMI VAR\\**\\s*$"), "")
    val rec = app.importText(text, folder = source.folder) ?: run {
        if (app.message == null) app.message = "Panodaki cevap okunamadı."
        return null
    }
    // importText falls back to the open folder when the source has none: the source's folder is what counts
    if (rec.let { app.store.document(it.id)?.folder } != source.folder) app.setFolder(rec.id, source.folder)
    val title = if (rec.title.startsWith("Genişletme")) rec.title else "Genişletme · ${rec.title}"
    app.rename(rec.id, title)
    app.store.update(rec.id) { it.copy(author = source.title) }
    app.message = "“$title” kitaplığa eklendi."
    return rec.id
}

