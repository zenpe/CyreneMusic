package com.cyrene.music

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.Equalizer
import android.os.Bundle
import android.util.Log
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : AudioServiceFragmentActivity() {
    private var androidEqualizer: Equalizer? = null
    private var equalizerSessionId: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 必须在 super.onCreate() 之前调用 installSplashScreen()
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d("MainActivity", "🔧 开始配置 Flutter Engine")

        try {
            // 注册悬浮歌词插件
            val floatingPlugin = FloatingLyricPlugin()
            flutterEngine.plugins.add(floatingPlugin)
            Log.d("MainActivity", "✅ 悬浮歌词插件注册成功: ${floatingPlugin::class.java.simpleName}")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 悬浮歌词插件注册失败: ${e.message}", e)
        }

        try {
            // 注册 Android 媒体通知插件
            val mediaNotificationPlugin = AndroidMediaNotificationPlugin()
            flutterEngine.plugins.add(mediaNotificationPlugin)
            Log.d("MainActivity", "✅ 媒体通知插件注册成功: ${mediaNotificationPlugin::class.java.simpleName}")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 媒体通知插件注册失败: ${e.message}", e)
        }

        // 注册广播接收器
        val filter = android.content.IntentFilter("com.cyrene.music.action.STOP_SLEEP_TIMER")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
             registerReceiver(sleepTimerReceiver, filter, android.content.Context.RECEIVER_NOT_EXPORTED)
        } else {
             registerReceiver(sleepTimerReceiver, filter)
        }

        // 注册睡眠定时器 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cyrene.music/sleep_timer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val endTimeMs = call.argument<Long>("endTimeMs") ?: 0L
                        SleepTimerService.start(this, endTimeMs)
                        result.success(null)
                    }
                    "stop" -> {
                        SleepTimerService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cyrene.music/system_volume")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "getVolume" -> {
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        if (max <= 0) {
                            result.success(0.0)
                        } else {
                            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                            result.success(current.toDouble() / max.toDouble())
                        }
                    }
                    "setVolume" -> {
                        val raw = call.argument<Double>("volume") ?: 0.0
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        if (max > 0) {
                            val target = (raw.coerceIn(0.0, 1.0) * max).roundToInt()
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cyrene.music/android_equalizer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "attach" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: -1
                        result.success(attachAndroidEqualizer(sessionId))
                    }
                    "apply" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val gains = call.argument<List<Double>>("gains") ?: emptyList()
                        val frequencies = call.argument<List<Int>>("frequencies") ?: emptyList()
                        result.success(applyAndroidEqualizer(enabled, gains, frequencies))
                    }
                    "release" -> {
                        releaseAndroidEqualizer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun attachAndroidEqualizer(sessionId: Int): Boolean {
        if (sessionId <= 0) return false
        if (equalizerSessionId == sessionId && androidEqualizer != null) return true

        releaseAndroidEqualizer()
        return try {
            androidEqualizer = Equalizer(0, sessionId)
            equalizerSessionId = sessionId
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Android EQ attach 失败: ${e.message}", e)
            false
        }
    }

    private fun applyAndroidEqualizer(
        enabled: Boolean,
        gains: List<Double>,
        frequencies: List<Int>,
    ): Boolean {
        val eq = androidEqualizer ?: return false

        return try {
            val bandLevelRange = eq.bandLevelRange
            val minLevel = bandLevelRange[0].toInt()
            val maxLevel = bandLevelRange[1].toInt()

            // 每次应用前先清零，避免历史参数叠加。
            for (band in 0 until eq.numberOfBands.toInt()) {
                eq.setBandLevel(band.toShort(), 0)
            }

            if (!enabled) {
                eq.enabled = false
                return true
            }

            eq.enabled = true

            if (gains.isNotEmpty() && frequencies.isNotEmpty()) {
                val count = minOf(gains.size, frequencies.size)
                for (i in 0 until count) {
                    val targetBand = eq.getBand((frequencies[i] * 1000))
                    val level = (gains[i] * 100.0).roundToInt()
                        .coerceIn(minLevel, maxLevel)
                        .toShort()
                    eq.setBandLevel(targetBand, level)
                }
            } else if (gains.isNotEmpty()) {
                val bandCount = minOf(gains.size, eq.numberOfBands.toInt())
                for (i in 0 until bandCount) {
                    val level = (gains[i] * 100.0).roundToInt()
                        .coerceIn(minLevel, maxLevel)
                        .toShort()
                    eq.setBandLevel(i.toShort(), level)
                }
            }
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Android EQ apply 失败: ${e.message}", e)
            false
        }
    }

    private fun releaseAndroidEqualizer() {
        try {
            androidEqualizer?.release()
        } catch (e: Exception) {
            Log.w("MainActivity", "⚠️ Android EQ release 异常: ${e.message}")
        } finally {
            androidEqualizer = null
            equalizerSessionId = null
        }
    }

    private val sleepTimerReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.cyrene.music.action.STOP_SLEEP_TIMER") {
                Log.d("MainActivity", "📱 收到睡眠定时器取消广播，通知 Flutter 侧停止")
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    io.flutter.plugin.common.MethodChannel(messenger, "com.cyrene.music/sleep_timer")
                        .invokeMethod("onTimerCancelled", null)
                }
            }
        }
    }

    override fun onDestroy() {
        releaseAndroidEqualizer()
        try {
            unregisterReceiver(sleepTimerReceiver)
        } catch (e: Exception) {
            // 忽略未注册的异常
        }
        super.onDestroy()
    }
}

