// Voice notes (port of Speech/NoteRecorder.swift): records from the microphone (the headset's when one is connected)
// into an .m4a; `transcribe` writes its text on the device when the system can (Android 13+ recognises a file).
package com.fatihgocgun.wisepath.notes

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import kotlin.coroutines.resume

class NoteRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    val isRecording: Boolean get() = recorder != null

    val hasPermission: Boolean
        get() = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun start(): Boolean {
        if (recorder != null) return true
        if (!hasPermission) return false
        val f = File(context.cacheDir, "note-${System.currentTimeMillis()}.m4a")
        val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        return runCatching {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioEncodingBitRate(64_000)
            r.setAudioSamplingRate(44_100)
            r.setOutputFile(f.path)
            r.prepare()
            r.start()
            recorder = r
            file = f
            startedAt = SystemClock.elapsedRealtime()
            true
        }.getOrElse { runCatching { r.release() }; false }
    }

    /** The recording and its length in seconds; null when nothing usable was recorded. */
    fun stop(): Pair<File, Double>? {
        val r = recorder ?: return null
        recorder = null
        val seconds = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
        val ok = runCatching { r.stop() }.isSuccess
        runCatching { r.release() }
        val f = file ?: return null
        file = null
        if (!ok || seconds < 0.5) { f.delete(); return null }
        return f to seconds
    }

    fun cancel() {
        val r = recorder ?: return
        recorder = null
        runCatching { r.stop() }
        runCatching { r.release() }
        file?.delete()
        file = null
    }

    /** The note's words, recognised on the device (Android 13+ with an on-device recogniser); "" when not possible. */
    suspend fun transcribe(audio: File, language: String = "tr-TR"): String {
        if (Build.VERSION.SDK_INT < 33) return ""
        return withContext(Dispatchers.Main) {
            if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) return@withContext ""
            // the recogniser reads raw audio from a pipe; the m4a is decoded to PCM first
            val pcm = withContext(Dispatchers.IO) { runCatching { AudioDecode.toPcm16Mono(audio) }.getOrNull() } ?: return@withContext ""
            withTimeoutOrNull(60_000) {
                suspendCancellableCoroutine { cont ->
                    val rec = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                    val pipe = ParcelFileDescriptor.createPipe()
                    Thread {
                        runCatching { ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]).use { it.write(pcm.first) } }
                    }.start()
                    rec.setRecognitionListener(object : RecognitionListener {
                        override fun onResults(results: Bundle) {
                            val t = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
                            rec.destroy(); if (cont.isActive) cont.resume(t)
                        }
                        override fun onError(error: Int) { rec.destroy(); if (cont.isActive) cont.resume("") }
                        override fun onReadyForSpeech(params: Bundle?) {}
                        override fun onBeginningOfSpeech() {}
                        override fun onRmsChanged(rmsdB: Float) {}
                        override fun onBufferReceived(buffer: ByteArray?) {}
                        override fun onEndOfSpeech() {}
                        override fun onPartialResults(partialResults: Bundle?) {}
                        override fun onEvent(eventType: Int, params: Bundle?) {}
                    })
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
                        putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                        putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT)
                        putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, pcm.second)
                    }
                    cont.invokeOnCancellation { rec.destroy() }
                    rec.startListening(intent)
                }
            } ?: ""
        }
    }
}

/** Decodes an audio file to 16-bit mono PCM (bytes, sample rate). */
object AudioDecode {
    fun toPcm16Mono(file: File): Pair<ByteArray, Int> {
        val ex = android.media.MediaExtractor()
        ex.setDataSource(file.path)
        val track = (0 until ex.trackCount).first { ex.getTrackFormat(it).getString(android.media.MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
        ex.selectTrack(track)
        val fmt = ex.getTrackFormat(track)
        val codec = android.media.MediaCodec.createDecoderByType(fmt.getString(android.media.MediaFormat.KEY_MIME)!!)
        codec.configure(fmt, null, null, 0)
        codec.start()
        val out = java.io.ByteArrayOutputStream()
        val info = android.media.MediaCodec.BufferInfo()
        var inputDone = false
        var channels = fmt.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT)
        var rate = fmt.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
        while (true) {
            if (!inputDone) {
                val i = codec.dequeueInputBuffer(10_000)
                if (i >= 0) {
                    val buf = codec.getInputBuffer(i)!!
                    val n = ex.readSampleData(buf, 0)
                    if (n < 0) { codec.queueInputBuffer(i, 0, 0, 0, android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true }
                    else { codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0); ex.advance() }
                }
            }
            val o = codec.dequeueOutputBuffer(info, 10_000)
            if (o == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                channels = codec.outputFormat.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT)
                rate = codec.outputFormat.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
            } else if (o >= 0) {
                val buf = codec.getOutputBuffer(o)!!
                val bytes = ByteArray(info.size)
                buf.position(info.offset); buf.get(bytes)
                if (channels <= 1) out.write(bytes) else {
                    // keep the first channel
                    var k = 0
                    while (k + 1 < bytes.size) { out.write(bytes[k].toInt()); out.write(bytes[k + 1].toInt()); k += 2 * channels }
                }
                codec.releaseOutputBuffer(o, false)
                if (info.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        }
        codec.stop(); codec.release(); ex.release()
        return out.toByteArray() to rate
    }
}
