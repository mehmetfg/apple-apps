// What the statistics pages count (port of StatsModel in StatsViews.swift and its extension in StatsDash.swift).
// Everything is derived: listening from the ListeningLog, marks from the highlights' dates, notes from the NoteStore,
// finished books from DocumentRecord.finishes. 225 words = 1 page. Weeks start on Monday.
package com.fatihgocgun.wisepath.stats

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.notes.ReaderNote
import com.fatihgocgun.wisepath.ui.Palette
import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

enum class StatSpan(val label: String) { day("Gün"), week("Hafta"), month("Ay") }

/** One bar of the chart: a day, a week or a month. */
data class StatBucket(
    val start: LocalDate, val label: String, val minutes: Double, val words: Int, val current: Boolean, val finished: Int = 0,
) {
    val pages: Double get() = words / ListeningLog.WORDS_PER_PAGE
    val pace: Double get() = if (minutes > 0.5) words / minutes else 0.0
}

data class DayStat(val date: LocalDate, val minutes: Double, val words: Int) {
    val pages: Double get() = words / ListeningLog.WORDS_PER_PAGE
}

data class FinishedBook(val doc: DocumentRecord, val at: Long) { val id: String get() = "${doc.id}-$at" }

data class Records(val streak: Int, val best: Int, val top: DayStat?)
data class WeekDelta(val now: Double, val before: Double, val change: Double?)
data class BookTime(val doc: DocumentRecord?, val title: String, val minutes: Double, val words: Int)
data class NoteCounts(val voice: Int, val text: Int, val seconds: Double)

/**
 * A snapshot of the numbers, made once per recomposition key (the log's revision, the library, the notes).
 * Cheap enough: the log is a map of days.
 */
class StatsModel(val app: AppModel, val docs: List<DocumentRecord>, val notes: List<ReaderNote>) {
    private val log = app.log
    val today: LocalDate = LocalDate.now()
    private val zone = ZoneId.systemDefault()

    private fun millis(d: LocalDate): Long = d.atStartOfDay(zone).toInstant().toEpochMilli()

    /** The period `offset` periods from the current one: a day, Monday–Sunday, a calendar month (both ends included). */
    fun range(s: StatSpan, offset: Int = 0): Pair<LocalDate, LocalDate> = when (s) {
        StatSpan.day -> today.plusDays(offset.toLong()).let { it to it }
        StatSpan.week -> today.with(DayOfWeek.MONDAY).plusWeeks(offset.toLong()).let { it to it.plusDays(6) }
        StatSpan.month -> today.withDayOfMonth(1).plusMonths(offset.toLong()).let { it to it.plusMonths(1).minusDays(1) }
    }

    /** Books put into the library in the period. */
    fun added(s: StatSpan, offset: Int = 0): Int {
        val (a, z) = range(s, offset)
        val from = millis(a); val to = millis(z.plusDays(1))
        return docs.count { it.addedAt in from until to }
    }

    /** The bars that end at the period `offset`: 14 days, 8 weeks or 6 months. */
    fun buckets(s: StatSpan, offset: Int = 0): List<StatBucket> {
        val count = when (s) { StatSpan.day -> 14; StatSpan.week -> 8; StatSpan.month -> 6 }
        val f = DateTimeFormatter.ofPattern(if (s == StatSpan.month) "MMM" else "d MMM", Format.tr)
        return (count - 1 downTo 0).map { i ->
            val o = offset - i
            val (a, z) = range(s, o)
            val t = log.total(a, z)
            val label = if (s == StatSpan.day && o == 0) "Bugün" else f.format(a)
            StatBucket(a, label, t.seconds / 60, t.words, current = i == 0, finished = finished(s, o).size)
        }
    }

    /** Days of the period that have come (today included); a past period counts all its days. */
    fun daysSoFar(s: StatSpan, offset: Int = 0): Int {
        val (a, z) = range(s, offset)
        val end = if (z.isBefore(today)) z else today
        return maxOf(1, ChronoUnit.DAYS.between(a, end).toInt() + 1)
    }

    /** Days of the period on which something was listened. */
    fun activeDays(s: StatSpan, offset: Int = 0): Int {
        val a = range(s, offset).first
        return (0 until daysSoFar(s, offset)).count { log.day(a.plusDays(it.toLong())).seconds / 60 >= STREAK_FLOOR }
    }

    fun total(s: StatSpan, offset: Int = 0): ListeningDay {
        val (a, z) = range(s, offset)
        return log.total(a, z)
    }

    /** Daily averages over every day since the log began: the number of days and the sum. */
    val averages: Pair<Int, ListeningDay>?
        get() {
            val first = log.firstDay ?: return null
            val n = maxOf(1, ChronoUnit.DAYS.between(first, today).toInt() + 1)
            return n to log.total(first, today)
        }

    fun marks(s: StatSpan, offset: Int = 0): Int {
        val (a, z) = range(s, offset)
        val from = millis(a); val to = millis(z.plusDays(1))
        return docs.sumOf { d -> d.highlights.count { it.createdAt in from until to } }
    }

    fun notes(s: StatSpan, offset: Int = 0): NoteCounts {
        val (a, z) = range(s, offset)
        val from = millis(a); val to = millis(z.plusDays(1))
        val ns = notes.filter { it.date in from until to }
        return NoteCounts(ns.count { it.hasVoice }, ns.count { !it.hasVoice }, ns.sumOf { it.seconds ?: 0.0 })
    }

    private fun doc(id: String) = docs.firstOrNull { it.id == id }

    /** Listening by folder (Felsefe, Bilimler…), minutes. */
    fun folders(t: ListeningDay): List<Pair<String, Double>> {
        val by = LinkedHashMap<String, Double>()
        for ((id, v) in t.docs) {
            val d = doc(id)
            val name = if (d == null) "Silinen" else d.folder ?: "Klasörsüz"
            by[name] = (by[name] ?: 0.0) + v.seconds / 60
        }
        return by.map { it.key to it.value }.filter { it.second >= 0.5 }.sortedByDescending { it.second }
    }

    fun books(t: ListeningDay): List<BookTime> = t.docs.map { (id, v) ->
        val d = doc(id)
        BookTime(d, d?.title ?: "Silinen belge", v.seconds / 60, v.words)
    }.filter { it.minutes >= 0.5 }.sortedByDescending { it.minutes }

    // MARK: the dashboard (StatsDash.swift)

    /** Monday … Sunday of the week `offset` weeks from this one. */
    fun week(offset: Int = 0): List<DayStat> {
        val a = range(StatSpan.week, offset).first
        return (0 until 7).map { i ->
            val d = a.plusDays(i.toLong())
            val x = log.day(d)
            DayStat(d, x.seconds / 60, x.words)
        }
    }

    val todayStat: DayStat get() = log.day(today).let { DayStat(today, it.seconds / 60, it.words) }

    /** The run of days (today not yet reached does not break it), the longest run, and the best day. */
    val records: Records by lazy {
        val first = log.firstDay ?: return@lazy Records(0, 0, null)
        var run = 0; var best = 0
        var top: DayStat? = null
        var d = first
        while (!d.isAfter(today)) {
            val x = log.day(d)
            val m = x.seconds / 60
            if (m >= STREAK_FLOOR) { run++; best = maxOf(best, run) } else if (d.isBefore(today)) run = 0
            if (m > (top?.minutes ?: 0.0)) top = DayStat(d, m, x.words)
            d = d.plusDays(1)
        }
        Records(run, best, top)
    }

    /** This week up to today against the same days of last week (change null when last week had nothing). */
    val weekDelta: WeekDelta
        get() {
            val n = ChronoUnit.DAYS.between(range(StatSpan.week).first, today).toInt() + 1
            val now = week(0).take(n).sumOf { it.minutes }
            val before = week(-1).take(n).sumOf { it.minutes }
            return WeekDelta(now, before, if (before >= 1) (now - before) / before else null)
        }

    /** Books heard to their end between two days (both included), newest first. A book read twice counts twice. */
    fun finished(a: LocalDate, z: LocalDate): List<FinishedBook> {
        val from = millis(a); val to = millis(z.plusDays(1))
        return docs.flatMap { d -> d.finishes.filter { it in from until to }.map { FinishedBook(d, it) } }.sortedByDescending { it.at }
    }

    fun finished(s: StatSpan, offset: Int = 0): List<FinishedBook> = range(s, offset).let { finished(it.first, it.second) }

    /** The unfinished book nearest its end, and the listening left in it (seconds). */
    val nearest: Pair<DocumentRecord, Double>?
        get() = docs.filter { !it.isFinished && !it.isUnread && it.length > 0 }.maxByOrNull { it.progress }
            ?.let { it to app.duration(maxOf(0, it.length - it.position), it.speed) }

    companion object {
        /** A day counts towards the run of days once this much was listened. */
        const val STREAK_FLOOR = 5.0
    }
}

object StatFormat {
    fun minutes(m: Double): String {
        val t = Math.round(m).toInt()
        if (t < 60) return "$t dk"
        return if (t % 60 == 0) "${t / 60} sa" else "${t / 60} sa ${t % 60} dk"
    }

    fun number(n: Int): String = NumberFormat.getIntegerInstance(Format.tr).format(n)

    fun pages(words: Int): String {
        if (words == 0) return "0"
        val p = words / ListeningLog.WORDS_PER_PAGE
        return if (p < 10) decimal(p) else number(Math.round(p).toInt())
    }

    fun decimal(v: Double): String = String.format(java.util.Locale.US, "%.1f", v).replace('.', ',')

    /** "3 sa 20 dk" / "45 dk" (HomeShelf's InventoryStrip.hours: truncated, not rounded). */
    fun hours(seconds: Double): String {
        val h = (seconds / 3600).toInt()
        return if (h >= 1) "$h sa ${((seconds % 3600) / 60).toInt()} dk" else "${(seconds / 60).toInt()} dk"
    }

    fun percent(v: Double): String = "%" + Math.round(v * 100).toInt()

    val dayMonth: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM", Format.tr)
    fun dayMonth(d: LocalDate): String = dayMonth.format(d)
    fun dayMonth(millis: Long): String = dayMonth.format(Format.localDate(millis))
}

object StatTint {
    val orange = Color(1.0f, 0.62f, 0.20f)
    val sky = Color(0.30f, 0.70f, 1.0f)
    val violet = Color(0.52f, 0.42f, 0.98f)
    val mint = Color(0.20f, 0.80f, 0.62f)
    val rose = Color(1.0f, 0.40f, 0.56f)
    val amber = Color(0.98f, 0.70f, 0.10f)
    val green = Color(0xFF34C759)
    val hot = Brush.verticalGradient(listOf(orange, Palette.play))
    val cool = Brush.verticalGradient(listOf(sky, violet))
    val done = Brush.verticalGradient(listOf(mint, Color(0.10f, 0.62f, 0.50f)))

    /** A bar's colour: today warm, a day that reached the goal green, the others cool. */
    fun bar(today: Boolean, reached: Boolean): Brush = if (today) hot else if (reached) done else cool

    val weekdays = listOf("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz")

    /** The pie's colours, in order. */
    val pie = listOf(violet, mint, orange, sky, rose, Color(0xFFFFCC00), Color(0xFF5856D6), Color(0xFFA2845E), Color(0xFF30B0C7), Color.Gray)
}
