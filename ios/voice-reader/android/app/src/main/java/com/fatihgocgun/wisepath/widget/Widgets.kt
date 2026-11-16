// Wise Path's home-screen widgets (port of WisePathWidgets/*.swift and ReadingCardWidget.swift), read from the
// snapshot WidgetFeed writes:
//   Okumaya devam  the book to go on with: cover, title, chapter, progress; ▶/⏸ and İşaretle run in the app without
//                  opening it; a tap on the card opens the book (wisepath://book/<id>)
//   Bugün          today's listening against the daily goal, and the last seven days; a tap opens İstatistik
package com.fatihgocgun.wisepath.widget

import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.MainActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

private val Amber = Color(0xFFED9E38)

private fun link(context: Context, url: String) =
    actionStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url), context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))

private fun minutesText(m: Double): String = if (m >= 60) "${m.toInt() / 60} sa ${m.toInt() % 60} dk" else "${m.roundToInt()} dk"

@Composable
private fun Empty(text: String) {
    Box(GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 12.sp))
    }
}

@Composable
private fun Bar(value: Double) {
    LinearProgressIndicator(
        progress = value.toFloat().coerceIn(0f, 1f),
        modifier = GlanceModifier.fillMaxWidth().height(4.dp),
        color = ColorProvider(Amber),
        backgroundColor = GlanceTheme.colors.surfaceVariant,
    )
}

// MARK: - Okumaya devam

class ReadingCardWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(120.dp, 120.dp), DpSize(250.dp, 120.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snap = withContext(Dispatchers.IO) { WidgetFeed.load(context) }
        val cover = snap?.current?.let { b -> withContext(Dispatchers.IO) { WidgetFeed.cover(context, b.id) } }
        provideContent { GlanceTheme { ReadingCard(context, snap, cover) } }
    }
}

@Composable
private fun ReadingCard(context: Context, snap: WidgetSnapshot?, cover: android.graphics.Bitmap?) {
    val b = snap?.current
    val wide = LocalSize.current.width >= 230.dp
    Column(GlanceModifier.fillMaxSize().background(GlanceTheme.colors.widgetBackground).cornerRadius(18.dp).padding(12.dp)) {
        if (b == null) { Empty("Bir kitap aç, burada kalsın."); return@Column }
        Row(GlanceModifier.fillMaxWidth().defaultWeight().clickable(link(context, "wisepath://book/${b.id}"))) {
            val w = if (wide) 58.dp else 40.dp
            if (cover != null) {
                Image(ImageProvider(cover), contentDescription = null, modifier = GlanceModifier.size(w, w * 1.5f).cornerRadius(5.dp))
            } else {
                Box(GlanceModifier.size(w, w * 1.5f).background(Color(0xFF4A4A8A)).cornerRadius(5.dp), contentAlignment = Alignment.Center) {
                    Text(b.title.take(1), style = TextStyle(color = ColorProvider(Color.White), fontWeight = FontWeight.Bold))
                }
            }
            Spacer(GlanceModifier.width(10.dp))
            Column(GlanceModifier.defaultWeight()) {
                if (wide) Text("OKUMAYA DEVAM", style = TextStyle(color = ColorProvider(Amber), fontSize = 10.sp, fontWeight = FontWeight.Bold))
                Text(b.title, maxLines = 2, style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 14.sp, fontWeight = FontWeight.Medium))
                val sub = b.chapter ?: b.author
                if (sub != null) Text(sub, maxLines = 1, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 11.sp))
                if (wide) Text(b.status, maxLines = 1, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 11.sp))
            }
        }
        Spacer(GlanceModifier.height(6.dp))
        Bar(b.progress)
        Spacer(GlanceModifier.height(6.dp))
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(GlanceModifier.defaultWeight().height(34.dp).background(GlanceTheme.colors.secondaryContainer).cornerRadius(17.dp)
                .clickable(actionRunCallback<ToggleReadingAction>()), contentAlignment = Alignment.Center) {
                Image(ImageProvider(Icon.createWithResource("android", if (snap.playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)),
                    contentDescription = if (snap.playing) "Durdur" else "Oku", modifier = GlanceModifier.size(22.dp))
            }
            Spacer(GlanceModifier.width(8.dp))
            Box(GlanceModifier.defaultWeight().height(34.dp).background(ColorProvider(Amber.copy(alpha = 0.25f))).cornerRadius(17.dp)
                .clickable(actionRunCallback<MarkSentenceAction>()), contentAlignment = Alignment.Center) {
                Text("İşaretle", style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 13.sp, fontWeight = FontWeight.Medium))
            }
        }
    }
}

/** Oku / Durdur: the reading goes on from its place, or stops — the app is not opened. */
class ToggleReadingAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        withContext(Dispatchers.Main) { AppModel.get(context).remotePlay() }
        WidgetFeed.update(context, now = true)
    }
}

/** Cümleyi işaretle: the sentence being read turns yellow (a second press takes it away). */
class MarkSentenceAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        withContext(Dispatchers.Main) { AppModel.get(context).markSpokenSentence() }
    }
}

class ReadingCardWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ReadingCardWidget()
}

// MARK: - Bugün (today and the goal)

class TodayWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(120.dp, 120.dp), DpSize(250.dp, 120.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snap = withContext(Dispatchers.IO) { WidgetFeed.load(context) }
        provideContent { GlanceTheme { Today(context, snap) } }
    }
}

@Composable
private fun Today(context: Context, s: WidgetSnapshot?) {
    val wide = LocalSize.current.width >= 230.dp
    val minutes = s?.todayMinutes ?: 0.0
    val goal = s?.goalMinutes ?: 0
    Row(GlanceModifier.fillMaxSize().background(GlanceTheme.colors.widgetBackground).cornerRadius(18.dp).padding(12.dp)
        .clickable(link(context, "wisepath://stats")), verticalAlignment = Alignment.Bottom) {
        Column(GlanceModifier.defaultWeight()) {
            Text(if (wide) "BUGÜN DİNLEDİĞİN" else "BUGÜN", style = TextStyle(color = ColorProvider(Amber), fontSize = 10.sp, fontWeight = FontWeight.Bold))
            Text(minutesText(minutes), style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = if (wide) 28.sp else 24.sp, fontWeight = FontWeight.Bold))
            Text("${(s?.todayPages ?: 0.0).roundToInt()} sayfa", style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 12.sp))
            if (goal > 0) {
                Spacer(GlanceModifier.height(6.dp))
                Bar(minutes / goal)
                Text(if (minutes >= goal) "Hedef tamam · $goal dk" else "Hedef $goal dk · ${(goal - minutes).roundToInt()} dk kaldı",
                    maxLines = 1, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp))
            }
            if (wide) s?.current?.let { Text(it.title, maxLines = 1, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp)) }
        }
        if (wide) {
            Spacer(GlanceModifier.width(12.dp))
            Week(s?.week ?: emptyList(), 70)
        }
    }
}

@Composable
private fun Week(days: List<WidgetSnapshot.Day>, height: Int) {
    val peak = maxOf(1.0, days.maxOfOrNull { it.minutes } ?: 1.0)
    Row(verticalAlignment = Alignment.Bottom) {
        days.forEach { d ->
            Column(GlanceModifier.padding(horizontal = 2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(GlanceModifier.width(7.dp).height(maxOf(3, ((height - 14) * d.minutes / peak).toInt()).dp)
                    .background(if (d.today) ColorProvider(Amber) else GlanceTheme.colors.outline).cornerRadius(3.dp)) {}
                Text(d.label, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 8.sp))
            }
        }
    }
}

class TodayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayWidget()
}
