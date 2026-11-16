// Wise Path as a real media app: a foreground service with a MediaSession, so reading goes on with the screen off,
// the lock screen and the notification show the book with ⏮ ⏯ ⏭, and headphone / Bluetooth keys work.
// ⏮ ⏭ move by the chosen unit (in the moving modes: ⏭ marks the sentence, ⏮ records a voice note — AppModel decides).
package com.fatihgocgun.wisepath.speech

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.MainActivity
import com.fatihgocgun.wisepath.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class PlaybackService : Service() {
    private lateinit var session: MediaSessionCompat
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var foreground = false

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) AppModel.get(context).player.becameNoisy()
        }
    }

    override fun onCreate() {
        super.onCreate()
        val app = AppModel.get(this)
        createChannel()
        session = MediaSessionCompat(this, "WisePath").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = app.remotePlay()
                override fun onPause() = app.remotePause()
                override fun onStop() = app.player.pause()
                override fun onSkipToNext() = app.remoteNext()
                override fun onSkipToPrevious() = app.remotePrevious()
                override fun onFastForward() = app.player.skip(true, com.fatihgocgun.wisepath.settings.NavigationUnit.seconds30)
                override fun onRewind() = app.player.skip(false, com.fatihgocgun.wisepath.settings.NavigationUnit.seconds30)
                override fun onSeekTo(pos: Long) = app.seekToMillis(pos)
            })
            setSessionActivity(openAppIntent())
            isActive = true
        }
        ContextCompat.registerReceiver(this, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_NOT_EXPORTED)
        scope.launch {
            app.player.state
                .map { Triple(it.documentID to it.title, it.isPlaying to it.isSpeaking, (it.cursor / 200) to it.speed) }
                .distinctUntilChanged()
                .collect { update() }
        }
        scope.launch { app.store.coverVersion.collect { update() } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)
        update()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        scope.cancel()
        runCatching { unregisterReceiver(noisy) }
        session.isActive = false
        session.release()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val app = AppModel.get(this)
        if (!app.player.isPlaying) { app.store.saveNow(); stopSelf() }
    }

    private fun update() {
        val app = AppModel.get(this)
        val s = app.player.state.value
        val millisPerChar = 1000.0 / (app.player.charsPerSecond * s.speed)
        val duration = (s.length * millisPerChar).toLong()
        val position = (s.cursor * millisPerChar).toLong()
        val actions = PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_FAST_FORWARD or PlaybackStateCompat.ACTION_REWIND or PlaybackStateCompat.ACTION_STOP
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (s.isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    position, if (s.isPlaying) s.speed.toFloat() else 0f,
                )
                .build()
        )
        val doc = s.documentID?.let { app.store.document(it) }
        val chapter = app.player.nav.chapterTitle(s.cursor)
        val cover = s.documentID?.let { id -> runCatching { BitmapFactory.decodeFile(app.store.coverFile(id).path) }.getOrNull() }
        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, s.title.ifEmpty { "Wise Path" })
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, s.author ?: doc?.folder ?: "")
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, chapter ?: "")
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                .apply { if (cover != null) putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, cover) }
                .build()
        )
        if (!s.isSpeaking && s.documentID == null) {
            if (foreground) { stopForeground(STOP_FOREGROUND_REMOVE); foreground = false }
            stopSelf()
            return
        }
        val n = buildNotification(s.isPlaying, s.title, chapter ?: s.author ?: "", cover)
        if (s.isPlaying) {
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(NOTIFICATION_ID, n)
            foreground = true
        } else {
            // paused: the notification stays (to resume from it) but the service may be stopped by the system
            if (foreground) { stopForeground(STOP_FOREGROUND_DETACH); foreground = false }
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, n)
        }
    }

    private fun buildNotification(playing: Boolean, title: String, subtitle: String, cover: android.graphics.Bitmap?): Notification {
        fun action(icon: Int, label: String, a: Long) =
            NotificationCompat.Action(icon, label, MediaButtonReceiver.buildMediaButtonPendingIntent(this, a))
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title.ifEmpty { "Wise Path" })
            .setContentText(subtitle)
            .setLargeIcon(cover)
            .setContentIntent(openAppIntent())
            .setDeleteIntent(MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_STOP))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .addAction(action(android.R.drawable.ic_media_previous, "Geri", PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
            .addAction(
                if (playing) action(android.R.drawable.ic_media_pause, "Duraklat", PlaybackStateCompat.ACTION_PAUSE)
                else action(android.R.drawable.ic_media_play, "Oynat", PlaybackStateCompat.ACTION_PLAY)
            )
            .addAction(action(android.R.drawable.ic_media_next, "İleri", PlaybackStateCompat.ACTION_SKIP_TO_NEXT))
            .setStyle(MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Okuma", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Okunan kitap ve oynatma düğmeleri"
                setShowBadge(false)
            })
        }
    }

    companion object {
        const val CHANNEL = "reading"
        const val NOTIFICATION_ID = 7

        fun start(context: Context) {
            val i = Intent(context, PlaybackService::class.java)
            runCatching { ContextCompat.startForegroundService(context, i) }
                .onFailure { runCatching { context.startService(i) } }
        }
    }
}
