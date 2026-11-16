// The app's side of the widgets (port of VoiceReader/WidgetFeed.swift and Shared/WidgetSnapshot.swift). `update`
// writes a small snapshot — the book to go on with (title, chapter, progress, cover), whether it is playing, today's
// and the week's listening, the daily goal — a second after the last call, so a burst of changes writes once, and
// asks the widgets to redraw. The widgets only read the snapshot; their keys run AppModel through ActionCallbacks.
//   files/WisePath/widget.json            the snapshot
//   files/WisePath/widget-covers/<id>.jpg  a small cover per book, written once
package com.fatihgocgun.wisepath.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.shortcuts.installShortcuts
import com.fatihgocgun.wisepath.stats.ListeningLog
import com.fatihgocgun.wisepath.store.LibraryStore
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.time.LocalDate

@Serializable
data class WidgetSnapshot(
    val current: Book? = null,
    val playing: Boolean = false,
    val todayMinutes: Double = 0.0,
    val todayPages: Double = 0.0,
    val goalMinutes: Int = 0,
    val week: List<Day> = emptyList(),
    val updated: Long = 0,
) {
    @Serializable
    data class Book(val id: String, val title: String, val author: String?, val chapter: String?, val progress: Double,
                    val status: String, val finished: Boolean)

    @Serializable
    data class Day(val label: String, val minutes: Double, val today: Boolean)
}

object WidgetFeed {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var pending: Job? = null
    private var attached = false

    fun root(context: Context) = File(context.filesDir, "WisePath")
    fun snapshotFile(context: Context) = File(root(context), "widget.json")
    fun coverFile(context: Context, id: String) = File(root(context), "widget-covers/$id.jpg")

    fun load(context: Context): WidgetSnapshot? =
        runCatching { AppJson.decodeFromString(WidgetSnapshot.serializer(), snapshotFile(context).readText()) }.getOrNull()

    /** The reading state or the log changed: write the snapshot a second after the last call (`now`: at once). */
    fun update(context: Context, now: Boolean = false) {
        val c = context.applicationContext
        pending?.cancel()
        pending = scope.launch {
            if (!now) delay(1000)
            write(c)
        }
    }

    /**
     * Optional: follows the player (book, playing, whole percents), the library and the log by itself, so nobody
     * has to call `update`. Call once (Modules.install).
     */
    fun attach(app: AppModel) {
        if (attached) return
        attached = true
        scope.launch {
            combine(
                app.player.state.map { Triple(it.documentID, it.isPlaying, (it.progress * 100).toInt()) }.distinctUntilChanged(),
                app.store.documents,
                app.log.revision,
            ) { a, _, _ -> a }.collect { update(app.context) }
        }
    }

    private suspend fun write(context: Context) {
        val app = AppModel.get(context)
        val docs = app.store.documents.value
        val state = app.player.state.value
        val playingDoc = state.documentID?.let { app.store.document(it) }
        val current = playingDoc ?: docs.filter { it.lastOpenedAt != null && !it.isFinished }.maxByOrNull { it.lastOpenedAt!! }
        val chapter = current?.let { d ->
            app.store.cachedContent(d.id)?.chapters?.sortedBy { it.offset }?.lastOrNull { it.offset <= d.position }?.title
        }
        val today = LocalDate.now()
        val day = app.log.day(today)
        val week = (6 downTo 0).map { back ->
            val d = today.minusDays(back.toLong())
            WidgetSnapshot.Day(Format.day(d, "EE").take(2), app.log.day(d).seconds / 60, back == 0)
        }
        val snap = WidgetSnapshot(
            current = current?.let {
                WidgetSnapshot.Book(it.id, it.title, it.author, chapter, it.progress, app.statusText(it), it.isFinished)
            },
            playing = state.isPlaying && state.documentID == current?.id,
            todayMinutes = day.seconds / 60,
            todayPages = day.words / ListeningLog.WORDS_PER_PAGE,
            goalMinutes = app.settings.dailyGoal,
            week = week,
            updated = System.currentTimeMillis(),
        )
        val coverSource = current?.let { app.store.coverFile(it.id) }
        withContext(Dispatchers.IO) {
            runCatching {
                snapshotFile(context).parentFile?.mkdirs()
                LibraryStore.atomicWrite(snapshotFile(context), AppJson.encodeToString(WidgetSnapshot.serializer(), snap))
            }
            if (current != null && coverSource != null) writeCover(context, current.id, coverSource)
        }
        runCatching { ReadingCardWidget().updateAll(context) }
        runCatching { TodayWidget().updateAll(context) }
        installShortcuts(context, current?.title)
    }

    /** A 240×360 cover for the widgets out of the book's own picture. Written once. */
    private fun writeCover(context: Context, id: String, source: File) {
        val out = coverFile(context, id)
        if (out.exists() || !source.exists()) return
        runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(source.path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 240 && bounds.outHeight / (sample * 2) >= 360) sample *= 2
            val img = BitmapFactory.decodeFile(source.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return
            val scale = maxOf(240f / img.width, 360f / img.height)
            val w = (img.width * scale).toInt().coerceAtLeast(240)
            val h = (img.height * scale).toInt().coerceAtLeast(360)
            val scaled = Bitmap.createScaledBitmap(img, w, h, true)
            val cropped = Bitmap.createBitmap(scaled, (w - 240) / 2, (h - 360) / 2, 240, 360)
            out.parentFile?.mkdirs()
            val tmp = File(out.parentFile, ".${out.name}.tmp")
            tmp.outputStream().use { cropped.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            tmp.renameTo(out)
        }
    }

    /** The small cover, if one was written. */
    fun cover(context: Context, id: String): Bitmap? {
        val f = coverFile(context, id)
        return if (f.exists()) runCatching { BitmapFactory.decodeFile(f.path) }.getOrNull() else null
    }
}
