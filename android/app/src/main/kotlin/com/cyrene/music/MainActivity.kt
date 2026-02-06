package com.cyrene.music

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : AudioServiceFragmentActivity() {

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
        try {
            unregisterReceiver(sleepTimerReceiver)
        } catch (e: Exception) {
            // 忽略未注册的异常
        }
        super.onDestroy()
    }
}

