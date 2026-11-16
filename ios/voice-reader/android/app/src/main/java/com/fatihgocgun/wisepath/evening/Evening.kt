// Akşam tekrarı (port of AppModel+Evening.swift, listening summary only — Teoria does not exist on Android): after
// each save of the listening log one local notification is planned for the evening time (22:30 unless changed):
// "Akşam tekrarı · bugün 35 dk dinledin" with "Felsefe 20 dk · Bilimler 15 dk". Under 3 minutes of listening, or with
// the reminder turned off, nothing is planned. Heard after the evening time: 20 minutes after the listening stops.
// No goals, no streaks: a day without listening asks for nothing. Planned with WorkManager (no exact-alarm permission,
// no manifest entry); a tap opens the statistics (wisepath://stats).
package com.fatihgocgun.wisepath.evening

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.MainActivity
import com.fatihgocgun.wisepath.R
import com.fatihgocgun.wisepath.TextFold
import com.fatihgocgun.wisepath.stats.ListeningLog
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/** The reminder's settings, in the app's own preferences (iOS keeps them in Teoria's shared defaults). */
object EveningSettings {
    private fun prefs(c: Context) = c.getSharedPreferences("evening", Context.MODE_PRIVATE)
    /** Below this, a day's listening asks for no evening reminder. */
    const val MINIMUM_MINUTES = 3.0

    fun enabled(c: Context) = prefs(c).getBoolean("evening.enabled", true)
    fun hour(c: Context) = prefs(c).getInt("evening.hour", 22)
    fun minute(c: Context) = prefs(c).getInt("evening.minute", 30)
    fun set(c: Context, enabled: Boolean = enabled(c), hour: Int = hour(c), minute: Int = minute(c)) {
        prefs(c).edit().putBoolean("evening.enabled", enabled).putInt("evening.hour", hour.coerceIn(0, 23))
            .putInt("evening.minute", minute.coerceIn(0, 59)).apply()
    }
}

private const val WORK = "wisepath.evening"
private const val CHANNEL = "evening"
private var planned: String? = null         // what is pending now: title|body|minute (null = nothing)

/**
 * The branch of a document (Teoria's rule, PDMListening.branch): the folder when it is one of the series, else the
 * first word of the title, else "Diğer".
 */
private fun branch(folder: String?, title: String): String {
    val names = mapOf("felsefe" to "Felsefe", "bilimler" to "Bilimler", "muhendislik" to "Mühendislik")
    folder?.let { f -> names[TextFold.fold(f.trim())]?.let { return it } }
    val first = TextFold.fold(title).split(Regex("[^\\p{L}\\p{N}]+")).firstOrNull { it.isNotEmpty() } ?: ""
    return names[first] ?: "Diğer"
}

/** The listening log was saved: plan (or take back) tonight's reminder. Cheap; call it after every log save. */
fun scheduleEvening(app: AppModel) {
    val c = app.context
    val wm = WorkManager.getInstance(c)
    val today = app.log.day(LocalDate.now())
    val perBranch = HashMap<String, Double>()
    for ((id, h) in today.docs) {
        val d = app.store.document(id)
        val b = if (d != null) branch(d.folder, d.title) else "Diğer"
        perBranch[b] = (perBranch[b] ?: 0.0) + h.seconds / 60
    }
    val total = perBranch.values.sum()
    if (!EveningSettings.enabled(c) || total < EveningSettings.MINIMUM_MINUTES) {
        if (planned != null) { wm.cancelUniqueWork(WORK); planned = null }
        return
    }
    val now = System.currentTimeMillis()
    var fire = LocalDateTime.now().withHour(EveningSettings.hour(c)).withMinute(EveningSettings.minute(c)).withSecond(0).withNano(0)
        .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
    if (fire < now + 60_000) fire = now + 20 * 60_000
    val order = listOf("Felsefe", "Bilimler", "Mühendislik", "Diğer")
    val parts = perBranch.filter { it.value >= 1 }.entries
        .sortedWith(compareBy({ order.indexOf(it.key).let { i -> if (i < 0) 9 else i } }, { -it.value }))
        .map { "${it.key} ${it.value.roundToInt()} dk" }
    val title = "Akşam tekrarı · bugün ${total.roundToInt()} dk dinledin"
    val body = if (parts.isEmpty()) "Bugün dinlediklerini bir kez daha düşün." else parts.joinToString(" · ")
    val key = "$title|$body|${fire / 60_000}"
    if (key == planned) return
    planned = key
    val req = OneTimeWorkRequestBuilder<EveningWorker>()
        .setInitialDelay(fire - now, TimeUnit.MILLISECONDS)
        .setInputData(workDataOf("title" to title, "body" to body, "at" to fire, "day" to ListeningLog.key(LocalDate.now())))
        .build()
    wm.enqueueUniqueWork(WORK, ExistingWorkPolicy.REPLACE, req)    // the same name replaces the one planned before
}

class EveningWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val at = inputData.getLong("at", 0)
        // a reminder held back for hours (the phone was off) is not news any more
        if (System.currentTimeMillis() - at > 3 * 3600_000L) return Result.success()
        if (!EveningSettings.enabled(applicationContext)) return Result.success()
        post(applicationContext, inputData.getString("title") ?: return Result.success(), inputData.getString("body") ?: "")
        return Result.success()
    }

    private fun post(c: Context, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val nm = c.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Akşam tekrarı", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("wisepath://stats"), c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(c, 7301, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        runCatching { NotificationManagerCompat.from(c).notify(7301, n) }
    }
}

/** Ayarlar: the reminder on or off, and its time. */
@Composable
fun EveningSettingsSection() {
    val context = LocalContext.current
    var on by remember { mutableStateOf(EveningSettings.enabled(context)) }
    var hour by remember { mutableStateOf(EveningSettings.hour(context)) }
    var minute by remember { mutableStateOf(EveningSettings.minute(context)) }
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().clickable {
            on = !on; EveningSettings.set(context, enabled = on); scheduleEvening(AppModel.get(context))
        }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Akşam tekrarı")
                Text("Gün içinde dinlediklerinin özeti, akşam bildirim olarak.", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
            }
            Switch(on, { on = it; EveningSettings.set(context, enabled = it); scheduleEvening(AppModel.get(context)) })
        }
        if (on) Row(Modifier.fillMaxWidth().clickable {
            TimePickerDialog(context, { _, h, m ->
                hour = h; minute = m
                EveningSettings.set(context, hour = h, minute = m)
                scheduleEvening(AppModel.get(context))
            }, hour, minute, true).show()
        }.padding(vertical = 8.dp)) {
            Text("Saat", Modifier.weight(1f))
            Text("%02d:%02d".format(hour, minute), color = MaterialTheme.colorScheme.primary)
        }
    }
}
