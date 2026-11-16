// Ayarlar (port of Views/SettingsView.swift): one page that opens each settings home. Reading settings live with the
// reader (Ses / Görsel), so this page gathers them for use outside a book, plus the app-wide pages.
package com.fatihgocgun.wisepath.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.settings.LibraryStyle
import com.fatihgocgun.wisepath.ui.Page
import com.fatihgocgun.wisepath.ui.Routes
import com.fatihgocgun.wisepath.ui.reader.AudioSettingsContent
import com.fatihgocgun.wisepath.ui.reader.ChoiceRow
import com.fatihgocgun.wisepath.ui.reader.SectionLabel
import com.fatihgocgun.wisepath.ui.reader.SliderRow
import com.fatihgocgun.wisepath.ui.reader.SwitchRow
import com.fatihgocgun.wisepath.ui.reader.VisualSettingsContent

@Composable
fun GeneralSettingsScreen(app: AppModel, nav: NavHostController) {
    var page by remember { mutableStateOf("") }
    val s = app.settings
    when (page) {
        "audio" -> Page("Ses Ayarları", { page = "" }) { pad ->
            Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
                AudioSettingsContent(app, onCloud = { nav.navigate(Routes.CLOUD) })
            }
        }
        "visual" -> Page("Görsel Ayarlar", { page = "" }) { pad ->
            Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
                VisualSettingsContent(s)
            }
        }
        else -> Page("Ayarlar", { nav.popBackStack() }) { pad ->
            Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
                SectionLabel("Okuma")
                Link("Ses Ayarları", "Hız, ses, müzik, okuma davranışı") { page = "audio" }
                Link("Görsel Ayarlar", "Yazı, tema, renk, konuşma imleci") { page = "visual" }
                Link("Bulut sesleri", "ElevenLabs, OpenAI, Google, Azure") { nav.navigate(Routes.CLOUD) }

                SectionLabel("Kitaplık")
                ChoiceRow(LibraryStyle.entries, s.style, { it.label }) { s.style = it }

                SectionLabel("Hedef")
                SliderRow("Günlük dinleme hedefi", s.dailyGoal.toDouble(), 10.0..240.0, steps = 22, shown = { "${it.toInt()} dk" }) {
                    s.dailyGoal = (it / 10).toInt() * 10
                }
                Link("İstatistikler", "Günler, kitaplar, seriler") { nav.navigate(Routes.STATS) }
                Link("Notlar", "Sesli ve yazılı notların hepsi") { nav.navigate(Routes.NOTES) }

                SectionLabel("Akşam tekrarı")
                com.fatihgocgun.wisepath.evening.EveningSettingsSection()

                SectionLabel("Hareket ve müzik")
                SwitchRow("Hareket kipi", s.bikeMode, "Kitap açılınca yol ekranı gelir (bisiklet, yürüyüş, koşu).") { s.bikeMode = it }
                Link("Yollar", "Kayıtlı sürüşler ve yürüyüşler") { nav.navigate(Routes.ROADS) }
                Link("Müzik kipi", "Okurken tam ekran sözler") { nav.navigate(Routes.MUSIC) }

                SectionLabel("Otomasyon ve eşitleme")
                Link("Otomasyon", "Saat, konum ve şarj kuralları") { nav.navigate(Routes.AUTOMATION) }
                Link("İstem oluştur", "Okunacak yeni metinler için istem") { nav.navigate(Routes.PROMPT) }
                Link("Eşitleme", "Klasör ile cihazlar arası yer, işaret ve not") { nav.navigate(Routes.SYNC) }
                Text("Wise Path · Android", Modifier.padding(top = 24.dp), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
            }
        }
    }
}

@Composable
private fun Link(title: String, note: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge)
        Text(note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
}
