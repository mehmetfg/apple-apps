// Ayarlar › Eşitleme: the shared folder (picked with the system folder picker, e.g. a folder a sync app mirrors from
// iCloud Drive › Voice Reader), this device's name, the last sync, "Şimdi eşitle", and the PDM vault copy.
package com.fatihgocgun.wisepath.sync

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.documentfile.provider.DocumentFile
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.ui.Page
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
fun SyncSettings(onBack: () -> Unit) {
    val context = LocalContext.current
    val app = remember { AppModel.get(context) }
    val engine = SyncEngine.instance
    val scope = rememberCoroutineScope()
    val s = app.settings
    val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    fun release(uri: String) {
        if (uri.isEmpty()) return
        runCatching { context.contentResolver.releasePersistableUriPermission(Uri.parse(uri), flags) }
    }
    fun folderName(uri: String): String =
        if (uri.isEmpty()) "—" else runCatching { DocumentFile.fromTreeUri(context, Uri.parse(uri))?.name }.getOrNull() ?: Uri.parse(uri).lastPathSegment ?: "?"

    val pickFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching { context.contentResolver.takePersistableUriPermission(uri, flags) }
        if (s.syncFolderUri != uri.toString()) release(s.syncFolderUri)
        s.syncFolderUri = uri.toString()
        engine?.folderChanged()
    }
    var vaultMessage by remember { mutableStateOf<String?>(null) }
    val pickVault = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri == null || engine == null) return@rememberLauncherForActivityResult
        runCatching { context.contentResolver.takePersistableUriPermission(uri, flags) }
        scope.launch {
            val old = engine.vault.uri
            val err = withContext(Dispatchers.IO) { engine.chooseVault(uri) }
            if (err == null) { if (old != uri.toString()) release(old) } else release(uri.toString())
            vaultMessage = err
        }
    }

    Page("Eşitleme", onBack) { pad ->
        Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            if (engine == null) {
                Text("Eşitleme bu sürümde kurulu değil.", Modifier.padding(16.dp))
                return@Column
            }

            Header("Klasör")
            Labeled("Eşitleme klasörü", folderName(s.syncFolderUri))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { pickFolder.launch(null) }) { Text(if (s.syncFolderUri.isEmpty()) "Klasör seç" else "Başka klasör seç") }
                if (s.syncFolderUri.isNotEmpty()) TextButton(onClick = {
                    release(s.syncFolderUri); s.syncFolderUri = ""; engine.folderChanged()
                }) { Text("Bağlantıyı kaldır", color = MaterialTheme.colorScheme.error) }
            }
            Footer("iPhone, Mac ve Claude'un paylaştığı iCloud Drive › Voice Reader klasörünün bu telefondaki kopyasını seç (örneğin bir eşitleme uygulamasının yansıttığı klasör). İçinde Loader, Library, State ve Events klasörleri olur; yoksa oluşturulur.")

            Header("Durum")
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(engine.status, Modifier.weight(1f))
                if (engine.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            }
            Labeled("Son eşitleme", if (engine.lastSync > 0) Format.date(engine.lastSync, "d MMMM HH:mm") else "henüz yok")
            engine.error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 4.dp)) }
            Button(onClick = { scope.launch { engine.syncNow() } }, enabled = s.syncFolderUri.isNotEmpty() && !engine.busy,
                modifier = Modifier.padding(top = 6.dp)) { Text("Şimdi eşitle") }
            Footer("Uygulama açılınca, ekrandayken üç dakikada bir, arka plana geçince ve arka planda on beş dakikada bir eşitlenir. Loader klasörüne bırakılan dosyalar kitaplığa eklenip Loader/Alındı'ya taşınır; alt klasör, kitaplıktaki klasör olur.")

            Header("Bu cihaz")
            var name by remember { mutableStateOf(s.deviceName) }
            OutlinedTextField(name, { v -> name = v.lowercase(Locale.ROOT).filter { it.isLetterOrDigit() || it == '-' } }, label = { Text("Cihaz adı") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            if (name != s.deviceName && name.isNotBlank()) {
                OutlinedButton(onClick = { s.deviceName = name; engine.folderChanged() }, modifier = Modifier.padding(top = 6.dp)) { Text("Adı kaydet") }
            }
            Footer("Bu cihazın dosyaları State/${s.deviceName}.json ve Events/${s.deviceName}.jsonl adıyla yazılır. Ad değişince diğer cihazlar onu yeni bir cihaz sayar.")

            Header("PDM vault kopyası")
            Labeled("Vault", if (engine.vault.connected) folderName(engine.vault.uri) else "seçilmedi")
            Labeled("Son yazma", engine.vaultStatus)
            vaultMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { pickVault.launch(null) }) { Text(if (engine.vault.connected) "Başka vault seç" else "Vault seç") }
                if (engine.vault.connected) TextButton(onClick = {
                    release(engine.vault.uri); engine.forgetVault(); vaultMessage = null
                }) { Text("Kaldır", color = MaterialTheme.colorScheme.error) }
            }
            Footer("Yerin, işaretlerin, notların ve dinleme kaydın Obsidian vault'unda _araçlar/voice-reader/durum klasörüne de yazılır; Mac, PDM merkezi ve Claude oradan okur. Vault'un kökünü (Personel Data Management) seç.")
            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun Header(text: String) {
    Text(text.uppercase(Locale("tr")), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
}

@Composable
private fun Labeled(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label)
        Spacer(Modifier.width(12.dp))
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
