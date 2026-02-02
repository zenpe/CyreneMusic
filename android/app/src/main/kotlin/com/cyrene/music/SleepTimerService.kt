package com.cyrene.music

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
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Android 睡眠定时器前台服务
 * 显示实时倒计时通知
 */
class SleepTimerService : Service() {

    companion object {
        private const val TAG = "SleepTimerService"
        private const val NOTIFICATION_ID = 20250201
        private const val CHANNEL_ID = "cyrene_sleep_timer"
        private const val CHANNEL_NAME = "睡眠定时器"
        
        private const val EXTRA_END_TIME = "extra_end_time"
        private const val ACTION_STOP_TIMER = "com.cyrene.music.action.STOP_SLEEP_TIMER"

        fun start(context: Context, endTimeMs: Long) {
            val intent = Intent(context, SleepTimerService::class.java).apply {
                putExtra(EXTRA_END_TIME, endTimeMs)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, SleepTimerService::class.java)
            context.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_TIMER) {
            // 用户点击了通知上的“取消”按钮
            // 发送广播给 MainActivity 处理（或者直接停止相关逻辑）
            // 这里我们发送一个广播，由 Flutter 端监听或者 MainActivity 转发展示
            // 简单起见，我们通过 sendBroadcast 发送给 MainActivity
            val broadcastIntent = Intent(ACTION_STOP_TIMER)
            // 设置包名确保只有自己能收到
            broadcastIntent.setPackage(packageName) 
            sendBroadcast(broadcastIntent)
            
            stopSelf()
            return START_NOT_STICKY
        }

        val endTimeMs = intent?.getLongExtra(EXTRA_END_TIME, 0L) ?: 0L
        if (endTimeMs > System.currentTimeMillis()) {
            startForegroundNotification(endTimeMs)
        } else {
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun startForegroundNotification(endTimeMs: Long) {
        val stopIntent = Intent(this, SleepTimerService::class.java).apply {
             action = ACTION_STOP_TIMER
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 
            0, 
            stopIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopTimeFormat = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
        val stopTimeString = stopTimeFormat.format(java.util.Date(endTimeMs))

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("睡眠定时器")
            .setContentText("预计停止时间: $stopTimeString") // 显示具体停止时间
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            
            // 关键：启用 Chronometer 倒计时，这会显示详细的剩余时间（如 10:25）
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setWhen(endTimeMs)
            .setShowWhen(true) // 确保时间显示
            
            // 添加取消按钮
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "取消", stopPendingIntent)

        // Android 14+ 前台服务类型适配
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
             startForeground(
                NOTIFICATION_ID, 
                builder.build(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE // 或者使用 dataSync/mediaPlayback 等，根据合规性选择
                // 注意：Android 14 要求明确类型。如果是纯计时器，SPECIAL_USE 需要说明。
                // 也可以复用 mediaPlayback 如果被视为媒体功能的一部分。
                // 暂时尝试 SPECIAL_USE 或不传 (如果 targetSdk < 34)
            )
        } else {
            startForeground(NOTIFICATION_ID, builder.build())
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_DEFAULT // 改为 DEFAULT 即可，HIGH 可能太打扰
                ).apply {
                    description = "显示睡眠定时器剩余时间"
                    setSound(null, null)
                    enableVibration(false)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }
}
