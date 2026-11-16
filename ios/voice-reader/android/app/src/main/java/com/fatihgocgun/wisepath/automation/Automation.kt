// Listening automations (port of Model/Automation.swift): a row of steps played one after another without touching
// the phone. A reading step takes a library folder's current book (the one last listened to and not finished) from
// where it was left, for so many minutes of listening; a pause step is a quiet thinking break with a short spoken
// announcement of what comes next. Kept in the app's own SharedPreferences as JSON, with the step each one was left
// at, so a stopped automation goes on from there.
package com.fatihgocgun.wisepath.automation

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.newId
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

@Serializable
enum class StepKind { read, pause }

@Serializable
data class AutomationStep(
    val id: String = newId(),
    val kind: StepKind,
    val folder: String? = null,         // read: the library folder
    val seconds: Int,                   // read: minutes of listening × 60 · pause: length of the break
) {
    val title: String get() = when (kind) {
        StepKind.read -> "${folder ?: "Klasör seçilmedi"} · ${AutoFormat.minutes(seconds)}"
        StepKind.pause -> "Düşünme arası · ${AutoFormat.clock(seconds)}"
    }

    companion object {
        fun read(folder: String, minutes: Int) = AutomationStep(kind = StepKind.read, folder = folder, seconds = minutes * 60)
        fun pause(seconds: Int) = AutomationStep(kind = StepKind.pause, folder = null, seconds = seconds)
    }
}

@Serializable
data class Automation(
    val id: String = newId(),
    val name: String,
    val steps: List<AutomationStep>,
) {
    val readingSeconds: Int get() = steps.filter { it.kind == StepKind.read }.sumOf { it.seconds }
    val totalSeconds: Int get() = steps.sumOf { it.seconds }

    companion object {
        /** The pilot (2026-10-23): philosophy, science, engineering, a minute's pause between them. */
        fun pilot() = Automation(name = "Üç dal · 15 dakika", steps = listOf(
            AutomationStep.read("Felsefe", 15), AutomationStep.pause(60),
            AutomationStep.read("Bilimler", 15), AutomationStep.pause(60),
            AutomationStep.read("Mühendislik", 15),
        ))
    }
}

/**
 * Where an automation was left: the step it was in and the listening already done in that step. Kept for each
 * automation, so each one goes on from its own place; cleared when it plays to its end.
 */
@Serializable
data class AutomationProgress(val stepID: String, val step: Int, val listened: Double, val savedAt: Long)

/** A place to go on from: the step and the seconds already heard in it. */
data class ResumePoint(val step: Int, val listened: Double)

class AutomationStore(context: Context) {
    private val prefs = context.getSharedPreferences("automations", Context.MODE_PRIVATE)
    private val listSerializer = ListSerializer(Automation.serializer())
    private val progressSerializer = MapSerializer(String.serializer(), AutomationProgress.serializer())

    var list by mutableStateOf<List<Automation>>(emptyList())
        private set
    var progress by mutableStateOf<Map<String, AutomationProgress>>(emptyMap())
        private set
    var lastRunID by mutableStateOf<String?>(null)
        private set

    init {
        list = prefs.getString(KEY, null)?.let { runCatching { AppJson.decodeFromString(listSerializer, it) }.getOrNull() } ?: emptyList()
        if (!prefs.getBoolean("automations.pilot", false)) {
            prefs.edit().putBoolean("automations.pilot", true).apply()
            list = listOf(Automation.pilot()) + list
            save()
        }
        val ids = list.map { it.id }.toSet()
        progress = (prefs.getString(PROGRESS_KEY, null)?.let { runCatching { AppJson.decodeFromString(progressSerializer, it) }.getOrNull() }
            ?: emptyMap()).filterKeys { it in ids }
        lastRunID = prefs.getString(LAST_KEY, null)
    }

    fun automation(id: String): Automation? = list.firstOrNull { it.id == id }

    /** The automation the library card offers: the one chosen or run last, else the first in the list. */
    val featured: Automation? get() = lastRunID?.let { automation(it) } ?: list.firstOrNull()

    fun select(id: String) {
        lastRunID = id
        prefs.edit().putString(LAST_KEY, id).apply()
    }

    fun upsert(a: Automation) {
        val i = list.indexOfFirst { it.id == a.id }
        list = if (i >= 0) list.toMutableList().also { it[i] = a } else list + a
        save()
    }

    fun delete(ids: Collection<String>) {
        val set = ids.toSet()
        list = list.filterNot { it.id in set }
        progress = progress.filterKeys { it !in set }
        save()
        saveProgress()
    }

    /** Moves the automation at `from` one place up (-1) or down (+1). */
    fun move(from: Int, by: Int) {
        val to = from + by
        if (from !in list.indices || to !in list.indices) return
        list = list.toMutableList().also { val a = it.removeAt(from); it.add(to, a) }
        save()
    }

    // MARK: where it was left

    /**
     * Where `a` goes on from, or null when it was not started or played to its end. A thinking break counts as done
     * once it began, and a reading step with only a few seconds left as read: going on starts with the next reading.
     * A step edited away falls back to the place it had.
     */
    fun resumePoint(a: Automation): ResumePoint? {
        val p = progress[a.id] ?: return null
        var i = a.steps.indexOfFirst { it.id == p.stepID }.takeIf { it >= 0 } ?: minOf(p.step, a.steps.size)
        var listened = if (i in a.steps.indices && a.steps[i].id == p.stepID) p.listened else 0.0
        while (i in a.steps.indices && (a.steps[i].kind == StepKind.pause || a.steps[i].seconds - listened <= 5)) {
            i += 1
            listened = 0.0
        }
        if (i !in a.steps.indices || !(i > 0 || listened > 0)) return null
        return ResumePoint(i, listened)
    }

    fun noteProgress(a: Automation, step: Int, listened: Double) {
        if (step !in a.steps.indices) { clearProgress(a.id); return }
        progress = progress + (a.id to AutomationProgress(a.steps[step].id, step, maxOf(0.0, listened), System.currentTimeMillis()))
        saveProgress()
    }

    fun clearProgress(id: String) {
        if (id !in progress) return
        progress = progress - id
        saveProgress()
    }

    private fun save() { prefs.edit().putString(KEY, AppJson.encodeToString(listSerializer, list)).apply() }
    private fun saveProgress() { prefs.edit().putString(PROGRESS_KEY, AppJson.encodeToString(progressSerializer, progress)).apply() }

    companion object {
        private const val KEY = "automations.v1"
        private const val PROGRESS_KEY = "automations.progress.v1"
        private const val LAST_KEY = "automations.last"
    }
}

enum class Phase { announcing, reading, thinking }

/** What an automation is doing now (shown in the mini player and the automation screen). */
data class AutomationRun(
    val automation: Automation,
    val step: Int = 0,
    val phase: Phase = Phase.announcing,
    val ending: Boolean = false,            // the last step is done, "Otomasyon bitti" is being said
    val documentTitle: String? = null,
    val phaseEnds: Long? = null,            // thinking: when the pause ends (wall clock ms)
    val stepSeconds: Double = 0.0,          // reading: the step's listening time
    val listenedBefore: Double = 0.0,       // reading: time already listened in this step (a book ended, the next went on)
) {
    val stepTitle: String get() {
        val s = automation.steps.getOrNull(step) ?: return ""
        return if (s.kind == StepKind.read) s.folder ?: "" else "Düşünme arası"
    }
    val position: String get() = "${step + 1}/${automation.steps.size}"
}

enum class SegmentOutcome { timeUp, finished, cancelled }

/**
 * An automation step's book is finished: go to the folder's next unfinished book, go on with the book that is
 * loaded, or stop. Answered on screen or with the headphone keys (⏭ next · ⏮ current).
 */
data class AutomationChoice(
    val finishedTitle: String?,     // null: the folder had no book yet
    val folder: String,
    val nextID: String?,
    val nextTitle: String?,
    val currentID: String?,
    val currentTitle: String?,
) {
    enum class Answer { next, current, stop }
}

object AutoFormat {
    /** 900 → "15 dk", 90 → "1,5 dk". */
    fun minutes(s: Int): String =
        if (s % 60 == 0) "${s / 60} dk" else String.format(java.util.Locale.US, "%.1f dk", s / 60.0).replace('.', ',')

    /** 75 → "1:15". */
    fun clock(s: Int): String = "${s / 60}:${"%02d".format(s % 60)}"
}
