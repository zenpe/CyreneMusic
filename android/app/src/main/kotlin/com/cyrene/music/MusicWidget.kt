package com.cyrene.music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.widget.RemoteViews
import android.graphics.BitmapFactory
import android.view.View
import java.io.File
import es.antonborri.home_widget.HomeWidgetPlugin

class MusicWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val rawTitle = widgetData.getString("title", "未在播放")
            val title = if (rawTitle == "Not Playing" || rawTitle.isNullOrEmpty()) "未在播放" else rawTitle
            val rawArtist = widgetData.getString("artist", "Cyrene Music")
            val artist = if (rawArtist.isNullOrEmpty()) "Cyrene Music" else rawArtist
            val isPlaying = widgetData.getBoolean("isPlaying", false)
            val albumArtPath = widgetData.getString("albumArtPath", "")
            val artVersion = widgetData.getLong("art_version", 0L)
            
            val isEnabled = widgetData.getBoolean("isEnabled", true)
            
            android.util.Log.d("MusicWidget", "🔄 更新小部件 ($appWidgetId): Title=$title, Artist=$artist, Playing=$isPlaying, Enabled=$isEnabled")

            val views = RemoteViews(context.packageName, R.layout.widget_music).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_artist, artist)

                // 处理启用/禁用状态的显示
                if (isEnabled) {
                    setViewVisibility(R.id.enabled_layout, View.VISIBLE)
                    setViewVisibility(R.id.disabled_layout, View.GONE)
                } else {
                    setViewVisibility(R.id.enabled_layout, View.GONE)
                    setViewVisibility(R.id.disabled_layout, View.VISIBLE)
                    setTextViewText(R.id.widget_disabled_text, context.getString(R.string.widget_enable_instructions))
                }

                // 播放/暂停图标
                setImageViewResource(
                    R.id.widget_play_pause,
                    if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
                )

                // 专辑封面处理 (优化：使用 artVersion 识别内容变化)
                if (albumArtPath?.isNotEmpty() == true) {
                    if (artVersion == lastArtVersion && lastBitmap != null) {
                        // 版本号没变，说明内容没变，直接使用缓存
                        setImageViewBitmap(R.id.widget_album_art, lastBitmap)
                    } else {
                        // 版本号变了，或者缓存失效，重新加载
                        val file = File(albumArtPath)
                        if (file.exists()) {
                            val bitmap = loadScaledBitmap(albumArtPath, 512, 512)
                            if (bitmap != null) {
                                // 添加圆角处理 (优化：使用位图宽度的 18% 作为圆角半径，确保正方形圆角视觉效果)
                                val radius = bitmap.width * 0.18f
                                val roundedBitmap = getRoundedCornerBitmap(bitmap, radius)
                                lastBitmap = roundedBitmap
                                lastArtVersion = artVersion
                                setImageViewBitmap(R.id.widget_album_art, roundedBitmap)
                            } else {
                                setImageViewResource(R.id.widget_album_art, R.drawable.ic_widget_note)
                            }
                        } else {
                            setImageViewResource(R.id.widget_album_art, R.drawable.ic_widget_note)
                        }
                    }
                } else {
                    lastArtVersion = -1L
                    lastBitmap = null
                    setImageViewResource(R.id.widget_album_art, R.drawable.ic_widget_note)
                }

                // 按钮点击事件 (使用 AudioService 的 MediaButtonReceiver 处理)
                val mediaButtonReceiver = android.content.ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                
                // 上一首
                val prevIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = mediaButtonReceiver
                    putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                }
                setOnClickPendingIntent(R.id.widget_prev, PendingIntent.getBroadcast(context, 101, prevIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))

                // 播放/暂停
                val playPauseIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = mediaButtonReceiver
                    putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                }
                setOnClickPendingIntent(R.id.widget_play_pause, PendingIntent.getBroadcast(context, 102, playPauseIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))

                // 下一首
                val nextIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = mediaButtonReceiver
                    putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_NEXT))
                }
                setOnClickPendingIntent(R.id.widget_next, PendingIntent.getBroadcast(context, 103, nextIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
                
                // 点击整个小部件或封面打开应用
                val appOpenIntent = Intent(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_album_art, PendingIntent.getActivity(context, 104, appOpenIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
                setOnClickPendingIntent(R.id.info_layout, PendingIntent.getActivity(context, 105, appOpenIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
                setOnClickPendingIntent(R.id.disabled_layout, PendingIntent.getActivity(context, 106, appOpenIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /**
     * 加载并缩放位图，防止 RemoteViews 内存溢出
     */
    private fun loadScaledBitmap(filePath: String, reqWidth: Int, reqHeight: Int): android.graphics.Bitmap? {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(filePath, options)

            // 计算缩放比例
            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
            options.inJustDecodeBounds = false
            
            BitmapFactory.decodeFile(filePath, options)
        } catch (e: Exception) {
            android.util.Log.e("MusicWidget", "Failed to load scaled bitmap: ${e.message}")
            null
        }
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val (height: Int, width: Int) = options.outHeight to options.outWidth
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2

            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    /**
     * 将位图裁剪为圆角矩形
     */
    private fun getRoundedCornerBitmap(bitmap: Bitmap, pixels: Float): Bitmap? {
        return try {
            val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val color = -0xbdbdbe
            val paint = Paint()
            val rect = Rect(0, 0, bitmap.width, bitmap.height)
            val rectF = RectF(rect)
            paint.isAntiAlias = true
            canvas.drawARGB(0, 0, 0, 0)
            paint.color = color
            canvas.drawRoundRect(rectF, pixels, pixels, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(bitmap, rect, rect, paint)
            output
        } catch (e: Exception) {
            bitmap
        }
    }

    companion object {
        private var lastArtVersion: Long = -1L
        private var lastBitmap: Bitmap? = null
    }
}
