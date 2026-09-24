package com.cyrene.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * 自定义 Android 媒体通知前台服务
 *
 * - 继续复用 audio_service 提供的 MediaBrowserService + MediaSession
 * - 接管通知 UI（通过 RemoteViews 自定义折叠与展开卡片，包含动态取色与进度条）
 */
class CustomMediaNotificationService : Service() {

    companion object {
        private const val TAG = "CustomMediaNotification"
        private const val NOTIFICATION_ID = 1124
        private const val CHANNEL_ID = "com.cyrene.music.channel.audio"
        private const val CHANNEL_NAME = "Cyrene Music"

        // 按钮动作 Action
        const val ACTION_PREV = "com.cyrene.music.action.PREV"
        const val ACTION_PLAY_PAUSE = "com.cyrene.music.action.PLAY_PAUSE"
        const val ACTION_NEXT = "com.cyrene.music.action.NEXT"
        const val ACTION_CYCLE_REPEAT_MODE = "com.cyrene.music.action.CYCLE_REPEAT_MODE"
        const val ACTION_TOGGLE_LYRIC = "com.cyrene.music.action.TOGGLE_LYRIC"

        private const val NOTIFICATION_UPDATE_DEBOUNCE_MS = 300L
        private const val MIN_UPDATE_INTERVAL_MS = 200L

        fun start(context: Context) {
            val intent = Intent(context, CustomMediaNotificationService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, CustomMediaNotificationService::class.java)
            context.stopService(intent)
        }
    }

    private var mediaBrowser: MediaBrowserCompat? = null
    private var mediaController: MediaControllerCompat? = null
    private var currentMetadata: MediaMetadataCompat? = null
    private var currentState: PlaybackStateCompat? = null
    private var wifiLock: android.net.wifi.WifiManager.WifiLock? = null

    // 防抖机制
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var pendingNotificationUpdate: Runnable? = null
    private var lastNotificationUpdateTime = 0L
    private var lastTitle: String? = null
    private var lastIsPlaying: Boolean? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        createNotificationChannel()

        // 通过 MediaBrowser 连接到 audio_service 的 MediaBrowserService
        mediaBrowser = MediaBrowserCompat(
            this,
            ComponentName(this, com.ryanheise.audioservice.AudioService::class.java),
            browserConnectionCallback,
            null
        ).apply {
            connect()
        }

        // 初始化 WiFiLock，确保后台流媒体播放不因 WiFi 休眠而中断
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
            wifiLock = wifiManager.createWifiLock(
                android.net.wifi.WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "CyreneMusic:WifiLock"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create WifiLock: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")

        when (intent?.action) {
            ACTION_PREV -> {
                mediaController?.transportControls?.skipToPrevious()
                return START_STICKY
            }
            ACTION_PLAY_PAUSE -> {
                val state = currentState ?: mediaController?.playbackState
                if (state?.state == PlaybackStateCompat.STATE_PLAYING) {
                    mediaController?.transportControls?.pause()
                } else {
                    mediaController?.transportControls?.play()
                }
                return START_STICKY
            }
            ACTION_NEXT -> {
                mediaController?.transportControls?.skipToNext()
                return START_STICKY
            }
            ACTION_CYCLE_REPEAT_MODE -> {
                handleCycleRepeatMode()
                return START_STICKY
            }
            ACTION_TOGGLE_LYRIC -> {
                handleToggleLyric()
                return START_STICKY
            }
        }

        // 如果已经有 controller 且有状态，确保前台通知存在
        mediaController?.let {
            scheduleNotificationUpdate()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        pendingNotificationUpdate?.let { handler.removeCallbacks(it) }
        pendingNotificationUpdate = null

        mediaController?.unregisterCallback(controllerCallback)
        mediaBrowser?.disconnect()
        mediaBrowser = null
        mediaController = null

        wifiLock?.let {
            if (it.isHeld) it.release()
        }
        wifiLock = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private val browserConnectionCallback = object : MediaBrowserCompat.ConnectionCallback() {
        override fun onConnected() {
            Log.d(TAG, "MediaBrowser connected")
            try {
                val browser = mediaBrowser ?: return
                val token = browser.sessionToken
                val controller = MediaControllerCompat(this@CustomMediaNotificationService, token)
                mediaController = controller
                controller.registerCallback(controllerCallback)

                currentMetadata = controller.metadata
                currentState = controller.playbackState
                scheduleNotificationUpdate()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create MediaController: ${e.message}", e)
            }
        }

        override fun onConnectionSuspended() {
            Log.w(TAG, "MediaBrowser connection suspended")
        }

        override fun onConnectionFailed() {
            Log.e(TAG, "MediaBrowser connection failed")
        }
    }

    private val controllerCallback = object : MediaControllerCompat.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadataCompat?) {
            currentMetadata = metadata
            scheduleNotificationUpdate()
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            performNotificationUpdate()
        }

        override fun onShuffleModeChanged(shuffleMode: Int) {
            performNotificationUpdate()
        }

        override fun onPlaybackStateChanged(state: PlaybackStateCompat?) {
            currentState = state

            val isPlaying = state?.state == PlaybackStateCompat.STATE_PLAYING

            try {
                wifiLock?.let { lock ->
                    if (isPlaying && !lock.isHeld) {
                        lock.acquire()
                        Log.d(TAG, "WifiLock acquired")
                    } else if (!isPlaying && lock.isHeld) {
                        lock.release()
                        Log.d(TAG, "WifiLock released")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "WifiLock management failed: ${e.message}")
            }

            if (lastIsPlaying != isPlaying) {
                performNotificationUpdate()
            } else {
                scheduleNotificationUpdate()
            }
        }
    }

    private fun scheduleNotificationUpdate() {
        pendingNotificationUpdate?.let { handler.removeCallbacks(it) }

        val now = System.currentTimeMillis()
        val timeSinceLastUpdate = now - lastNotificationUpdateTime

        val delay = if (timeSinceLastUpdate < MIN_UPDATE_INTERVAL_MS) {
            NOTIFICATION_UPDATE_DEBOUNCE_MS
        } else {
            50L
        }

        pendingNotificationUpdate = Runnable {
            performNotificationUpdate()
        }
        handler.postDelayed(pendingNotificationUpdate!!, delay)
    }

    private fun performNotificationUpdate() {
        pendingNotificationUpdate = null

        val controller = mediaController ?: return
        val playbackState = currentState ?: controller.playbackState
        val mediaMeta = currentMetadata ?: controller.metadata

        if (playbackState == null || mediaMeta == null) {
            return
        }

        val description = mediaMeta.description
        val newTitle = description.title?.toString()
        val newIsPlaying = playbackState.state == PlaybackStateCompat.STATE_PLAYING

        lastTitle = newTitle
        lastIsPlaying = newIsPlaying
        lastNotificationUpdateTime = System.currentTimeMillis()

        updateNotificationInternal(mediaMeta, playbackState)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Cyrene Music 媒体播放控制"
                    setShowBadge(false)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun updateNotificationInternal(
        metadata: MediaMetadataCompat,
        state: PlaybackStateCompat
    ) {
        val controller = mediaController ?: return
        val description: MediaDescriptionCompat = metadata.description
        val isPlaying = state.state == PlaybackStateCompat.STATE_PLAYING

        val title = description.title?.toString() ?: "Cyrene Music"
        val artist = description.subtitle?.toString() ?: description.description?.toString() ?: "未知歌手"
        val album = description.extras?.getString("album") ?: ""
        val durationMs = metadata.getLong(MediaMetadataCompat.METADATA_KEY_DURATION)
        val positionMs = state.position

        val progress = if (durationMs > 0) {
            ((positionMs.toDouble() / durationMs) * 1000).toInt().coerceIn(0, 1000)
        } else {
            0
        }

        // 加载并处理圆角封面图
        val artBitmap: Bitmap? = description.iconBitmap ?: loadIconFromUri(description.iconUri)
        val roundedArt: Bitmap? = if (artBitmap != null) {
            getRoundedCornerBitmap(artBitmap, 12f)
        } else null

        // 提取封面主色作为背景微光色
        val bgColor = if (artBitmap != null) {
            extractDominantDarkColor(artBitmap)
        } else {
            Color.argb(235, 26, 28, 35)
        }

        // 1. 构建折叠态（紧凑）视图
        val collapsedViews = RemoteViews(packageName, R.layout.notification_media_collapsed).apply {
            setTextViewText(R.id.notification_title, title)
            setTextViewText(R.id.notification_artist, artist)
            setInt(R.id.notification_root, "setBackgroundColor", bgColor)

            if (roundedArt != null) {
                setImageViewBitmap(R.id.notification_album_art, roundedArt)
            } else {
                setImageViewResource(R.id.notification_album_art, R.drawable.ic_notification)
            }

            setProgressBar(R.id.notification_progress, 1000, progress, false)

            // 按键图标与 PendingIntent
            setImageViewResource(
                R.id.notification_btn_play_pause,
                if (isPlaying) R.drawable.ic_notification_pause else R.drawable.ic_notification_play
            )
            setOnClickPendingIntent(R.id.notification_btn_prev, createActionPendingIntent(ACTION_PREV))
            setOnClickPendingIntent(R.id.notification_btn_play_pause, createActionPendingIntent(ACTION_PLAY_PAUSE))
            setOnClickPendingIntent(R.id.notification_btn_next, createActionPendingIntent(ACTION_NEXT))
        }

        // 2. 构建展开态（大卡片）视图
        val expandedViews = RemoteViews(packageName, R.layout.notification_media_expanded).apply {
            setTextViewText(R.id.notification_title, title)
            setTextViewText(R.id.notification_artist, artist)
            setTextViewText(R.id.notification_album, album)
            setViewVisibility(R.id.notification_album, if (album.isNotEmpty()) View.VISIBLE else View.GONE)
            setInt(R.id.notification_root, "setBackgroundColor", bgColor)

            if (roundedArt != null) {
                setImageViewBitmap(R.id.notification_album_art, roundedArt)
            } else {
                setImageViewResource(R.id.notification_album_art, R.drawable.ic_notification)
            }

            setProgressBar(R.id.notification_progress, 1000, progress, false)
            setTextViewText(R.id.notification_time_current, formatDuration(positionMs))
            setTextViewText(R.id.notification_time_total, formatDuration(durationMs))

            // 循环模式按键状态
            val repeatMode = controller.repeatMode
            val shuffleMode = controller.shuffleMode
            val modeRes = when {
                shuffleMode == PlaybackStateCompat.SHUFFLE_MODE_ALL -> R.drawable.ic_notification_shuffle
                repeatMode == PlaybackStateCompat.REPEAT_MODE_ONE -> R.drawable.ic_notification_repeat_one
                else -> R.drawable.ic_notification_repeat_all
            }
            setImageViewResource(R.id.notification_btn_mode, modeRes)

            setImageViewResource(
                R.id.notification_btn_play_pause,
                if (isPlaying) R.drawable.ic_notification_pause else R.drawable.ic_notification_play
            )

            setOnClickPendingIntent(R.id.notification_btn_mode, createActionPendingIntent(ACTION_CYCLE_REPEAT_MODE))
            setOnClickPendingIntent(R.id.notification_btn_prev, createActionPendingIntent(ACTION_PREV))
            setOnClickPendingIntent(R.id.notification_btn_play_pause, createActionPendingIntent(ACTION_PLAY_PAUSE))
            setOnClickPendingIntent(R.id.notification_btn_next, createActionPendingIntent(ACTION_NEXT))
            setOnClickPendingIntent(R.id.notification_btn_lyric, createActionPendingIntent(ACTION_TOGGLE_LYRIC))
        }

        // 3. 构建并发布通知
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setCustomContentView(collapsedViews)
            .setCustomBigContentView(expandedViews)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(isPlaying)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOnlyAlertOnce(true)
            .setContentIntent(createContentIntent())

        val notification: Notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createActionPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, CustomMediaNotificationService::class.java).apply {
            this.action = action
        }
        val requestCode = when (action) {
            ACTION_PREV -> 101
            ACTION_PLAY_PAUSE -> 102
            ACTION_NEXT -> 103
            ACTION_CYCLE_REPEAT_MODE -> 104
            ACTION_TOGGLE_LYRIC -> 105
            else -> 100
        }
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createContentIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)

        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun loadIconFromUri(uri: android.net.Uri?): Bitmap? {
        if (uri == null) return null
        return try {
            val uriString = uri.toString()
            if (uriString.startsWith("/") || uriString.startsWith("file://")) {
                val filePath = if (uriString.startsWith("file://")) {
                    uriString.removePrefix("file://")
                } else {
                    uriString
                }
                val file = java.io.File(filePath)
                if (file.exists()) {
                    BitmapFactory.decodeFile(filePath)
                } else null
            } else if (uriString.startsWith("content://")) {
                val stream = contentResolver.openInputStream(uri)
                stream?.use { BitmapFactory.decodeStream(it) }
            } else null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load icon from uri: $uri, ${e.message}")
            null
        }
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadiusDp: Float): Bitmap {
        return try {
            val density = resources.displayMetrics.density
            val radiusPx = cornerRadiusDp * density
            val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = Rect(0, 0, bitmap.width, bitmap.height)
            val rectF = RectF(rect)

            canvas.drawRoundRect(rectF, radiusPx, radiusPx, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(bitmap, rect, rect, paint)
            output
        } catch (e: Exception) {
            bitmap
        }
    }

    private fun extractDominantDarkColor(bitmap: Bitmap): Int {
        return try {
            val scaled = Bitmap.createScaledBitmap(bitmap, 16, 16, false)
            var redSum = 0L
            var greenSum = 0L
            var blueSum = 0L
            val count = 16 * 16
            for (x in 0 until 16) {
                for (y in 0 until 16) {
                    val pixel = scaled.getPixel(x, y)
                    redSum += (pixel shr 16) and 0xFF
                    greenSum += (pixel shr 8) and 0xFF
                    blueSum += pixel and 0xFF
                }
            }
            scaled.recycle()
            val avgR = (redSum / count).toInt()
            val avgG = (greenSum / count).toInt()
            val avgB = (blueSum / count).toInt()

            val factor = 0.35f
            val darkR = (avgR * factor).toInt().coerceIn(18, 48)
            val darkG = (avgG * factor).toInt().coerceIn(18, 48)
            val darkB = (avgB * factor).toInt().coerceIn(24, 60)
            Color.argb(235, darkR, darkG, darkB)
        } catch (e: Exception) {
            Color.argb(235, 26, 28, 35)
        }
    }

    private fun formatDuration(ms: Long): String {
        if (ms <= 0) return "00:00"
        val totalSeconds = ms / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format(Locale.US, "%02d:%02d", minutes, seconds)
    }

    private fun handleCycleRepeatMode() {
        val controller = mediaController ?: return
        try {
            controller.transportControls.sendCustomAction("cycle_repeat_mode", null)
            Log.d(TAG, "handleCycleRepeatMode: sent customAction cycle_repeat_mode")
        } catch (e: Exception) {
            Log.e(TAG, "handleCycleRepeatMode failed: ${e.message}", e)
        }
    }

    private fun handleToggleLyric() {
        val controller = mediaController ?: return
        try {
            controller.transportControls.sendCustomAction("toggle_floating_lyric", null)
            Log.d(TAG, "handleToggleLyric: sent customAction toggle_floating_lyric")
        } catch (e: Exception) {
            Log.e(TAG, "handleToggleLyric failed: ${e.message}", e)
        }
    }
}
