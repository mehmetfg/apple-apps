// The moving mode's foreground service (type location): it keeps the GPS record going with the screen off and the
// app in the background, as long as bikeMode is on. Its notification shows the way so far.
package com.fatihgocgun.wisepath.move

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class WorkoutService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var ticker: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val app = AppModel.get(this)
        if (!app.settings.bikeMode || !Workouts.hasLocationPermission(this)) { stopSelf(); return START_NOT_STICKY }
        channel()
        try {
            ServiceCompat.startForeground(this, ID, notification(), if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0)
        } catch (e: Exception) {
            // Android 14+: a location service may not start from the background
            Workouts.status = "Yol kaydı başlatılamadı"
            stopSelf(); return START_NOT_STICKY
        }
        Workouts.start(this, app.settings.moveKind)
        if (ticker == null) ticker = scope.launch {
            while (isActive) {
                delay(15_000)
                if (!app.settings.bikeMode) { stopSelf(); break }
                runCatching { getSystemService(NotificationManager::class.java).notify(ID, notification()) }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Workouts.finish()
        scope.cancel()
        super.onDestroy()
    }

    private fun channel() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null)
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Yol kaydı", NotificationManager.IMPORTANCE_LOW))
    }

    private fun notification(): Notification {
        val w = Workouts.current
        val kind = AppModel.get(this).settings.moveKind
        val text = if (w == null) "Yol kaydı" else
            "${MoveStrip.km(w.distance)} km · ${MoveStrip.clock(w.duration)} · ${Math.round(w.calories)} kcal"
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Yolda · ${kind.label}")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val CHANNEL = "wisepath.move"
        private const val ID = 4302

        /** Starts (or switches the kind of) the record; only with the location permission. */
        fun start(context: Context) {
            if (!Workouts.hasLocationPermission(context)) return
            runCatching { ContextCompat.startForegroundService(context, Intent(context, WorkoutService::class.java)) }
                .onFailure { Workouts.start(context, AppModel.get(context).settings.moveKind) }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, WorkoutService::class.java))
            Workouts.finish()
        }
    }
}

/**
 * Media keys while a moving mode is on: ⏭ marks the sentence being heard (again within a few seconds: the mark grows
 * back by one sentence), ⏮ starts or ends a voice note. Off the moving modes the keys do what they always do.
 * Called once from Modules.install.
 */
fun installRideKeys(app: AppModel) {
    Workouts.attach(app.context)
    app.remoteNextOverride = {
        if (!app.settings.bikeMode) false else {
            val c = app.markChain
            if (c != null && c.doc == app.player.documentID && System.currentTimeMillis() - c.at < 4000) app.extendMarkBack()
            else app.markSpokenSentence()
            true
        }
    }
    app.remotePreviousOverride = {
        if (!app.settings.bikeMode) false else { app.toggleVoiceNote(); true }
    }
}

/** Whether the sentence being heard is marked (the mark key shows "Kaldır"). */
fun AppModel.spokenSentenceMarked(): Boolean = sentenceNow()?.let { isMarked(it) } ?: false
