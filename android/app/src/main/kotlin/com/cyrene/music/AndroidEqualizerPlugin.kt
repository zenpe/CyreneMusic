package com.cyrene.music

import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.ln
import kotlin.math.roundToInt

/** Engine-owned EQ. Native work is serial; the pending slot always holds the newest intent. */
class AndroidEqualizerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val revision = AtomicLong(0)
    private var alive = true
    private var running = false
    private var requestedSession: Int? = null
    private var requestedId: Long? = null
    private var pending: Work? = null
    // Accessed only by worker.
    private var equalizer: Equalizer? = null
    private var session: Int? = null
    private data class Work(val call: MethodCall, val result: MethodChannel.Result?, val revision: Long)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.cyrene.music/android_equalizer")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("configure", "release", "invalidate")) {
            result.notImplemented(); return
        }
        val id = call.argument<Number>("sessionId")?.toInt()
        val requestId = call.argument<Number>("requestId")?.toLong()
        if (call.method == "invalidate" && requestId != requestedId) {
            result.success(mapOf("status" to "superseded")); return
        }
        if (call.method != "configure" && id != null && requestedSession != id) {
            result.success(mapOf("status" to "superseded")); return
        }
        if (call.method == "configure") {
            requestedSession = id
            requestedId = requestId
        }
        val next = Work(call, result, revision.incrementAndGet())
        pending?.result?.success(mapOf("status" to "superseded"))
        pending = next
        drain()
    }

    private fun drain() {
        if (running) return
        val work = pending ?: return
        pending = null
        running = true
        worker.execute {
            val response = try { execute(work) } catch (error: Exception) {
                Log.w("AndroidEqualizer", "Effect operation failed: ${work.call.method}", error)
                release()
                mapOf("status" to "failed")
            }
            if (revision.get() != work.revision) release()
            main.post {
                work.result?.success(if (revision.get() == work.revision) response else mapOf("status" to "superseded"))
                running = false
                if (alive) drain() else {
                    worker.execute { release() }
                    worker.shutdown()
                }
            }
        }
    }

    private fun execute(work: Work): Map<String, Any> {
        fun current() = revision.get() == work.revision
        if (!current()) return mapOf("status" to "superseded")
        val call = work.call
        if (call.method != "configure" || call.argument<Boolean>("enabled") != true) {
            release()
            return mapOf("status" to "disabled")
        }
        val id = call.argument<Number>("sessionId")?.toInt() ?: -1
        require(id > 0)
        val frequencies = call.argument<List<Number>>("frequencies")!!.map { it.toInt() }
        val gains = call.argument<List<Number>>("gains")!!.map { it.toDouble() }
        require(frequencies.isNotEmpty() && frequencies.size == gains.size)
        require(frequencies.all { it > 0 } && frequencies.zipWithNext().all { it.first < it.second })
        require(gains.all { it.isFinite() && it in -12.0..12.0 })
        if (session != id || equalizer == null) {
            release()
            equalizer = Equalizer(0, id)
            session = id
        }
        val eq = equalizer!!
        check(eq.hasControl())
        val centers = (0 until eq.numberOfBands.toInt()).map { eq.getCenterFreq(it.toShort()) / 1000 }
        require(centers.isNotEmpty() && centers.all { it > 0 } && centers.zipWithNext().all { it.first < it.second })
        val range = eq.bandLevelRange
        val min = maxOf(-1200, range[0].toInt())
        val max = minOf(1200, range[1].toInt())
        require(min < max && min <= 0 && max >= 0)
        val levels = centers.map { frequency ->
            val upper = frequencies.indexOfFirst { it >= frequency }
            val gain = when {
                upper == 0 -> gains.first()
                upper < 0 -> gains.last()
                else -> {
                    val ratio = ln(frequency.toDouble() / frequencies[upper - 1]) /
                        ln(frequencies[upper].toDouble() / frequencies[upper - 1])
                    gains[upper - 1] + (gains[upper] - gains[upper - 1]) * ratio
                }
            }
            (gain * 100).roundToInt().coerceIn(min, max).toShort()
        }
        for (i in levels.indices) {
            if (!current()) return mapOf("status" to "superseded")
            if (eq.getBandLevel(i.toShort()) != levels[i]) eq.setBandLevel(i.toShort(), levels[i])
        }
        if (!current()) return mapOf("status" to "superseded")
        val enabled = levels.any { it.toInt() != 0 }
        if (eq.enabled != enabled) check(eq.setEnabled(enabled) == AudioEffect.SUCCESS)
        check(eq.enabled == enabled && eq.hasControl())
        // Some devices quantize band gains. Successful setters plus control/enabled
        // checks confirm application without rejecting legitimate hardware rounding.
        return mapOf("status" to if (enabled) "applied" else "bypassed",
            "frequencies" to centers, "minGain" to min / 100.0, "maxGain" to max / 100.0)
    }

    private fun release() {
        try { equalizer?.release() } catch (_: Exception) {
            // Cleanup failure must not strand the worker or its completion.
        } finally { equalizer = null; session = null }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        alive = false
        channel.setMethodCallHandler(null)
        revision.incrementAndGet()
        pending?.result?.success(mapOf("status" to "superseded"))
        pending = null
        if (!running) {
            worker.execute { release() }
            worker.shutdown()
        }
    }
}
