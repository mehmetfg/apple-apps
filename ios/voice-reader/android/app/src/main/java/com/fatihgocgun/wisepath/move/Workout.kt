// Yolda: a ride or a walk recorded while listening (port of Model/Workout.swift). The route comes from GPS
// (android.location.LocationManager, no Play services), the climb from the barometer (or the GPS height when the
// phone has none), the steps from the step counter; calories from body weight, speed and slope. It runs as long as
// the moving mode is on (WorkoutService keeps it alive with the screen off) and is written every half minute, so a
// closed app loses at most that much. Files: files/WisePath/workouts/<id>.json, in the iOS JSON shape.
package com.fatihgocgun.wisepath.move

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.Instant
import com.fatihgocgun.wisepath.model.newId
import com.fatihgocgun.wisepath.model.now
import com.fatihgocgun.wisepath.settings.MoveKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

val MoveKind.isBike get() = this == MoveKind.bike

@Serializable
data class Workout(
    val id: String = newId(),
    val kind: MoveKind,
    val start: Instant = now(),
    val end: Instant? = null,
    val lastAt: Instant = now(),          // the last moment recorded (an unfinished one is resumed if recent)
    val distance: Double = 0.0,           // metres
    val moving: Double = 0.0,             // seconds in motion
    val climb: Double = 0.0,              // metres up
    val descent: Double = 0.0,            // metres down
    val steps: Int = 0,
    val calories: Double = 0.0,           // kcal
    val maxSpeed: Double = 0.0,           // km/h
    val weight: Double = 0.0,             // kg used for the calories
    val route: List<List<Double>> = emptyList(),   // [latitude, longitude, altitude, seconds since start]
    val documents: List<String> = emptyList(),     // books listened to on the way
) {
    /** Seconds from the start to the end (or the last fix). */
    val duration: Double get() = ((end ?: lastAt) - start) / 1000.0
    val averageSpeed: Double get() = if (moving > 0) distance / moving * 3.6 else 0.0
}

/** The one recorder of the process: Compose state, so the screens follow it. */
object Workouts : LocationListener, SensorEventListener {
    var current by mutableStateOf<Workout?>(null); private set
    var speed by mutableStateOf(0.0); private set          // km/h now, smoothed
    var grade by mutableStateOf(0.0); private set          // slope now (0.05 = 5 %)
    var status by mutableStateOf("")
    var history by mutableStateOf<List<Workout>>(emptyList()); private set

    private var app: AppModel? = null
    private var last: Location? = null
    private var lastAltitude: Double? = null                // barometric (or GPS) height of the last counted step
    private var smoothPressureHeight: Double? = null
    private var hasBarometer = false
    private var stepsBefore = 0
    private var stepBase: Float? = null
    private var savedAt = 0L
    private val gradeWindow = ArrayList<Pair<Double, Double>>()   // (metres, GPS height)
    private var historyLoaded = false

    private fun folder(): File = File(app!!.root, "workouts").also { it.mkdirs() }

    /** Called once (Modules.install / the screens): the earlier ways are read off the main thread. */
    fun attach(context: Context) {
        if (app != null) return
        val a = AppModel.get(context)
        app = a
        a.scope.launch {
            val list = withContext(Dispatchers.IO) { readHistory(folder()) }
            adopt(list)
        }
    }

    private fun readHistory(dir: File): List<Workout> =
        (dir.listFiles { f -> f.name.endsWith(".json") } ?: emptyArray())
            .mapNotNull { f -> runCatching { AppJson.decodeFromString(Workout.serializer(), f.readText()) }.getOrNull() }
            .sortedByDescending { it.start }

    private fun adopt(list: List<Workout>) {
        if (historyLoaded) return
        historyLoaded = true
        val c = current
        history = if (c != null) listOf(c) + list.filter { it.id != c.id } else list
    }

    private fun ensureHistory() { if (!historyLoaded) adopt(readHistory(folder())) }

    // MARK: starting and ending

    /** Starts recording, or goes on with the last one of the same kind if it stopped less than half an hour ago. */
    fun start(context: Context, kind: MoveKind) {
        attach(context)
        if (current?.kind == kind) return
        ensureHistory()
        if (current != null) finish()
        val open = history.firstOrNull { it.end == null && it.kind == kind }
        if (open != null && now() - open.lastAt < 1_800_000) {
            current = open
            stepsBefore = open.steps
        } else {
            history.filter { it.end == null }.forEach { save(it.copy(end = it.lastAt)) }
            current = Workout(kind = kind, weight = app!!.settings.bodyWeight)
            stepsBefore = 0
        }
        last = null; lastAltitude = null; smoothPressureHeight = null; stepBase = null; gradeWindow.clear()
        startLocation(context)
        startSensors(context)
    }

    /** Ends the recording. A very short one (under a minute and 50 m) is not kept. */
    fun finish() {
        val ctx = app?.context ?: return
        val c = current ?: return
        runCatching { ctx.getSystemService(LocationManager::class.java)?.removeUpdates(this) }
        runCatching { ctx.getSystemService(SensorManager::class.java)?.unregisterListener(this) }
        val t = now()
        val w = c.copy(end = t, lastAt = t)
        current = null
        speed = 0.0; grade = 0.0
        if (w.duration < 60 && w.distance < 50) {
            File(folder(), "${w.id}.json").delete()
            history = history.filterNot { it.id == w.id }
            return
        }
        save(w)
    }

    fun hasLocationPermission(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun startLocation(context: Context) {
        if (!hasLocationPermission(context)) { status = "Konum izni yok: Ayarlar › Uygulamalar › Wise Path › İzinler"; return }
        val lm = context.getSystemService(LocationManager::class.java) ?: run { status = "Konum alınamıyor"; return }
        val provider = when {
            lm.allProviders.contains(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            lm.allProviders.contains(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> null
        } ?: run { status = "Bu telefonda konum yok"; return }
        status = if (lm.isProviderEnabled(provider)) "Konum aranıyor…" else "Konum kapalı: hızlı ayarlardan açın"
        runCatching { lm.requestLocationUpdates(provider, 1000L, 3f, this, Looper.getMainLooper()) }
            .onFailure { status = "Konum alınamadı, yeniden deneniyor…" }
    }

    private fun startSensors(context: Context) {
        val sm = context.getSystemService(SensorManager::class.java) ?: return
        val pressure = sm.getDefaultSensor(Sensor.TYPE_PRESSURE)
        hasBarometer = pressure != null
        if (pressure != null) sm.registerListener(this, pressure, SensorManager.SENSOR_DELAY_NORMAL)
        val stepsOk = Build.VERSION.SDK_INT < 29 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        val counter = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (stepsOk && counter != null) sm.registerListener(this, counter, SensorManager.SENSOR_DELAY_NORMAL)
    }

    // MARK: sensors

    override fun onSensorChanged(e: SensorEvent) {
        val c = current ?: return
        when (e.sensor.type) {
            Sensor.TYPE_PRESSURE -> {
                val h = SensorManager.getAltitude(SensorManager.PRESSURE_STANDARD_ATMOSPHERE, e.values[0]).toDouble()
                val s = smoothPressureHeight?.let { it * 0.85 + h * 0.15 } ?: h
                smoothPressureHeight = s
                altitude(s)
            }
            Sensor.TYPE_STEP_COUNTER -> {
                // the counter counts since boot: only the steps after the first reading are ours
                val v = e.values[0]
                val base = stepBase ?: v.also { stepBase = it }
                current = c.copy(steps = stepsBefore + (v - base).toInt())
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** Height: climb and descent count steps of at least a metre (the sensor's noise stays out). */
    private fun altitude(h: Double, step: Double = 1.0) {
        val c = current ?: return
        val a = lastAltitude ?: run { lastAltitude = h; return }
        val d = h - a
        if (d >= step) { current = c.copy(climb = c.climb + d); lastAltitude = h }
        else if (d <= -step) { current = c.copy(descent = c.descent - d); lastAltitude = h }
    }

    // MARK: location

    override fun onLocationChanged(l: Location) { take(l) }
    override fun onProviderEnabled(provider: String) { status = "Konum aranıyor…" }
    override fun onProviderDisabled(provider: String) { status = "Konum kapalı: hızlı ayarlardan açın" }
    @Deprecated("old API") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    /**
     * One GPS fix: a poor one or a jump faster than a car is left out; the rest adds distance, time in motion,
     * slope and calories, and every fourth second or so a point of the route.
     */
    fun take(l: Location) {
        var w = current ?: return
        if (!l.hasAccuracy() || l.accuracy > 30) return
        status = "GPS · ±${l.accuracy.toInt()} m"
        val p = last
        var kmh = if (l.hasSpeed()) max(0.0, l.speed.toDouble()) * 3.6 else 0.0
        // no speed in the fix (it happens with a weak signal): from the way since the last one
        if (!l.hasSpeed() && p != null && l.time > p.time) {
            kmh = l.distanceTo(p) / ((l.time - p.time) / 1000.0) * 3.6
            if (kmh > 90) kmh = 0.0
        }
        speed = speed * 0.4 + kmh * 0.6
        try {
            w = w.copy(lastAt = l.time)
            nowListening()?.let { id -> if (id !in w.documents) w = w.copy(documents = w.documents + id) }
            if (p == null) {
                last = l
                w = w.copy(route = w.route + listOf(point(l, w)))
                return
            }
            val d = l.distanceTo(p).toDouble()
            val dt = (l.time - p.time) / 1000.0
            if (dt <= 0) return
            if (d / dt * 3.6 > 90) return                                      // a jump, not a movement
            val movingNow = d / dt * 3.6 > (if (w.kind.isBike) 3.0 else 1.5)
            if (d < 3 && !movingNow) return
            last = l
            w = w.copy(distance = w.distance + d)
            if (movingNow) w = w.copy(moving = w.moving + min(dt, 30.0), maxSpeed = max(w.maxSpeed, min(kmh, 80.0)))
            // slope over the last ~60 m, from the GPS height
            if (l.hasAltitude()) {
                gradeWindow.add(d to l.altitude)
                while (gradeWindow.size > 2 && gradeWindow.drop(1).sumOf { it.first } > 60) gradeWindow.removeAt(0)
                val sum = gradeWindow.drop(1).sumOf { it.first }
                val vOk = Build.VERSION.SDK_INT < 26 || !l.hasVerticalAccuracy() || l.verticalAccuracyMeters < 20
                if (sum > 20 && vOk) grade = ((l.altitude - gradeWindow.first().second) / sum).coerceIn(-0.25, 0.25)
                // no barometer: the climb from the GPS height, in coarser steps (its noise is a few metres)
                if (!hasBarometer) { current = w; altitude(l.altitude, 4.0); w = current ?: w }
            }
            if (movingNow) w = w.copy(calories = w.calories + calories(w.kind, d, min(dt, 30.0), grade, if (w.weight > 0) w.weight else 75.0))
            val lastT = w.route.lastOrNull()?.getOrNull(3)
            if (lastT != null && (l.time - w.start) / 1000.0 - lastT >= 4) w = w.copy(route = w.route + listOf(point(l, w)))
        } finally {
            if (current != null) { current = w; saveSoon() }
        }
    }

    private fun nowListening(): String? = app?.player?.let { if (it.isPlaying) it.documentID else null }

    private fun point(l: Location, w: Workout): List<Double> = listOf(
        (l.latitude * 1e6).roundToLong() / 1e6, (l.longitude * 1e6).roundToLong() / 1e6,
        Math.round(l.altitude).toDouble(), Math.round((l.time - w.start) / 1000.0).toDouble(),
    )

    /**
     * kcal for one stretch. Walking: ACSM's equation (oxygen = 3.5 + 0.1·v + 1.8·v·grade ml/kg/min, v in m/min,
     * 5 kcal a litre). Cycling: the Compendium's MET for the speed, plus the climb's work at 25 % efficiency.
     */
    fun calories(kind: MoveKind, metres: Double, seconds: Double, grade: Double, kg: Double): Double {
        val minutes = seconds / 60
        return if (!kind.isBike) {
            val v = metres / minutes
            val vo2 = 3.5 + 0.1 * v + 1.8 * v * max(0.0, grade)
            vo2 * kg / 1000 * 5 * minutes
        } else {
            val kmh = metres / seconds * 3.6
            val met = if (kmh < 16) 4.0 else if (kmh < 19) 6.8 else if (kmh < 22) 8.0 else if (kmh < 25) 10.0 else 12.0
            val climbWork = max(0.0, grade) * metres * (kg + 12) * 9.81 / 4184 / 0.25     // rider + ~12 kg bicycle
            met * kg * minutes / 60 + climbWork
        }
    }

    // MARK: saving

    private fun saveSoon() {
        val w = current ?: return
        if (now() - savedAt >= 30_000) save(w)
    }

    fun saveNow() { current?.let { save(it) } }

    fun save(w: Workout) {
        savedAt = now()
        history = if (history.any { it.id == w.id }) history.map { if (it.id == w.id) w else it } else listOf(w) + history
        val a = app ?: return
        val dir = folder()
        a.scope.launch(Dispatchers.IO) {
            runCatching {
                val target = File(dir, "${w.id}.json")
                val tmp = File(dir, "${w.id}.json.tmp")
                tmp.writeText(AppJson.encodeToString(Workout.serializer(), w))
                if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
            }
        }
    }
}
