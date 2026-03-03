import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'developer_mode_service.dart';

/// 通知操作回调
typedef NotificationActionCallback = void Function(String action, String? payload);

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  NotificationActionCallback? _actionCallback;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Linux initialization settings
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    final String? windowsIconPath =
        Platform.isWindows ? _resolveWindowsIconPath() : null;

    if (Platform.isWindows && windowsIconPath == null) {
      DeveloperModeService().addLog('⚠️ 未找到 Windows 通知图标，将使用空白图标');
    }

    final WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'Cyrene Music',
      appUserModelId: 'CyreneMusic.CyreneMusic.Desktop',
      guid: 'f5f2bb3e-5ca5-4cde-b61e-1464f93a4a85',
      iconPath: windowsIconPath,
    );

    // Darwin (iOS/macOS) initialization settings
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
      windows: initializationSettingsWindows,
    );

    try {
      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) async {
          print('🔔 [NotificationService] Notification clicked: ${details.payload}');
          print('🔔 [NotificationService] Action ID: ${details.actionId}');
          
          // 处理下载完成通知的操作
          final handled = await _handleDownloadNotificationAction(details);
          print('🔔 [NotificationService] Download notification handled: $handled');
          if (handled) {
            return; // 已处理，不继续传递
          }
          
          // 如果有操作ID，触发回调
          if (details.actionId != null && _actionCallback != null) {
            _actionCallback!(details.actionId!, details.payload);
          } else if (details.actionId == null && _actionCallback != null) {
            // 点击通知本身（不是按钮）
            _actionCallback!('tap', details.payload);
          }
        },
      );
      _isInitialized = true;
      DeveloperModeService().addLog('🔔 通知服务已初始化');
      
      // 针对 Windows 平台请求权限（虽然不一定必须，但有助于诊断）
      if (Platform.isWindows) {
        /* Windows 实现通常不需要显式请求权限，但我们可以尝试检查 */
        DeveloperModeService().addLog('🪟 Windows 平台通知初始化完成');
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ 通知服务初始化失败: $e');
    }
  }

  String? _resolveWindowsIconPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final candidates = <String>[
        p.join(
          exeDir.path,
          'data',
          'flutter_assets',
          'assets',
          'icons',
          'tray_icon.ico',
        ),
        p.join(Directory.current.path, 'assets', 'icons', 'tray_icon.ico'),
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
    } catch (e) {
      DeveloperModeService().addLog('⚠️ 解析 Windows 通知图标失败: $e');
      debugPrint('Failed to resolve Windows notification icon path: $e');
    }
    return null;
  }

  /// Send a simple notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'cyrene_music_channel',
      'Cyrene Music Notifications',
      channelDescription: 'Notifications for Cyrene Music',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const WindowsNotificationDetails windowsNotificationDetails =
        WindowsNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      windows: windowsNotificationDetails,
    );

    try {
      DeveloperModeService().addLog('🔔 尝试发送通知: $title');
      await _flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
      DeveloperModeService().addLog('✅ 通知发送请求已发出');
    } catch (e) {
      DeveloperModeService().addLog('❌ 发送通知失败: $e');
    }
  }

  /// 处理下载完成通知的操作
  /// 返回 true 表示已处理，false 表示未处理
  Future<bool> _handleDownloadNotificationAction(NotificationResponse details) async {
    final payload = details.payload;
    final actionId = details.actionId;
    
    print('🔍 [NotificationService] 检查下载通知: payload=$payload, actionId=$actionId');
    
    // 检查是否是下载完成通知（通过 payload）
    if (payload != null && payload.startsWith('download_complete:')) {
      final folderPath = payload.substring('download_complete:'.length);
      
      if (actionId == 'open_folder' || actionId == null) {
        // 点击"打开文件夹"按钮或点击通知本身
        print('📂 [NotificationService] 用户请求打开文件夹: $folderPath');
        DeveloperModeService().addLog('📂 用户请求打开下载文件夹: $folderPath');
        await openFolder(folderPath);
        return true;
      } else if (actionId == 'dismiss') {
        // 用户选择忽略
        print('🚫 [NotificationService] 用户忽略下载完成通知');
        return true;
      }
    }
    
    // 检查 Windows 平台的 arguments 格式（actionId 包含路径）
    if (actionId != null && actionId.startsWith('open_folder:')) {
      final folderPath = actionId.substring('open_folder:'.length);
      print('📂 [NotificationService] Windows 用户请求打开文件夹: $folderPath');
      DeveloperModeService().addLog('📂 用户请求打开下载文件夹: $folderPath');
      await openFolder(folderPath);
      return true;
    }
    
    // 检查 Windows 平台的 payload 格式（payload 也可能包含路径）
    if (payload != null && payload.startsWith('open_folder:')) {
      final folderPath = payload.substring('open_folder:'.length);
      print('📂 [NotificationService] Windows 用户请求打开文件夹 (via payload): $folderPath');
      DeveloperModeService().addLog('📂 用户请求打开下载文件夹: $folderPath');
      await openFolder(folderPath);
      return true;
    }
    
    // 检查忽略操作
    if (actionId == 'dismiss' || payload == 'dismiss') {
      print('🚫 [NotificationService] 用户忽略通知');
      return true;
    }
    
    return false;
  }

  /// 设置通知操作回调
  void setActionCallback(NotificationActionCallback callback) {
    _actionCallback = callback;
    print('🔔 [NotificationService] 通知操作回调已设置');
  }

  /// 显示带操作按钮的通知（用于恢复播放）
  Future<void> showResumePlaybackNotification({
    required String trackName,
    required String artist,
    String? coverUrl,
    String? platformInfo,  // 平台信息，如 "来自你的 Android"
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    // 下载封面图片（如果提供了URL）
    String? largeIconPath;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      largeIconPath = await _downloadCoverImage(coverUrl);
    }

    // 构建通知文本
    final hasPlatformInfo = platformInfo != null && platformInfo.isNotEmpty;
    final isWindowsPlatform = Platform.isWindows;
    final bodyBase = '$trackName - $artist';
    final notificationBody = bodyBase;
    final windowsSubtitle = isWindowsPlatform && hasPlatformInfo ? platformInfo : null;

    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'cyrene_music_playback',
      'Playback Control',
      channelDescription: 'Notifications for playback control',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Resume playback',
      subText: hasPlatformInfo ? platformInfo : null,
      // 添加大图标（专辑封面）- 圆形或方形小图标
      largeIcon: largeIconPath != null 
          ? FilePathAndroidBitmap(largeIconPath)
          : null,
      // 使用 BigPictureStyle 样式，显示长方形大图
      styleInformation: largeIconPath != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(largeIconPath),
              largeIcon: FilePathAndroidBitmap(largeIconPath),
              contentTitle: '从上次离开的位置继续？',
              summaryText: notificationBody,
              htmlFormatContentTitle: true,
              htmlFormatSummaryText: true,
              // 隐藏展开后的大图标，只显示大图（长方形）
              hideExpandedLargeIcon: true,
            )
          : null,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'resume',
          '继续播放',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'dismiss',
          '忽略',
        ),
      ],
    );

    final WindowsNotificationDetails windowsNotificationDetails =
        WindowsNotificationDetails(
      subtitle: windowsSubtitle,
      // Windows 使用 images 参数（复数），传入 WindowsImage 列表
      images: largeIconPath != null 
          ? <WindowsImage>[
              WindowsImage(
                Uri.file(largeIconPath, windows: true),
                altText: '专辑封面',
                // 不设置 crop，保持默认（圆角正方形）
                // 设置图片位置为应用徽标位置（显示在左侧小图标位置）
                placement: WindowsImagePlacement.appLogoOverride,
              ),
            ]
          : const <WindowsImage>[],
      actions: <WindowsAction>[
        WindowsAction(
          content: '继续播放',
          arguments: 'resume',
        ),
        WindowsAction(
          content: '忽略',
          arguments: 'dismiss',
        ),
      ],
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      windows: windowsNotificationDetails,
    );

    try {
      DeveloperModeService().addLog('🔔 显示恢复播放通知: $trackName');
      if (largeIconPath != null) {
        DeveloperModeService().addLog('🖼️ 封面图片: $largeIconPath');
      }
      
      await _flutterLocalNotificationsPlugin.show(
        id: 100, // 使用固定ID，避免重复通知
        title: '从上次离开的位置继续？',
        body: notificationBody,
        notificationDetails: notificationDetails,
        payload: payload,
      );
      DeveloperModeService().addLog('✅ 恢复播放通知已显示');
      if (platformInfo != null && platformInfo.isNotEmpty) {
        DeveloperModeService().addLog('📱 平台信息: $platformInfo');
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ 显示恢复播放通知失败: $e');
    }
  }

  /// 下载封面图片到本地
  Future<String?> _downloadCoverImage(String imageUrl) async {
    try {
      print('🖼️ [NotificationService] 开始下载封面: $imageUrl');
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final notificationDir = Directory(p.join(tempDir.path, 'notification_covers'));
      
      // 创建目录（如果不存在）
      if (!await notificationDir.exists()) {
        await notificationDir.create(recursive: true);
      }
      
      // 生成文件名（使用URL的hash）
      final fileName = 'cover_${imageUrl.hashCode.abs()}.jpg';
      final filePath = p.join(notificationDir.path, fileName);
      final file = File(filePath);
      
      // 如果是 Windows，检查圆角版本是否存在
      if (Platform.isWindows) {
        final roundedPath = filePath.replaceAll('.jpg', '_rounded.png');
        final roundedFile = File(roundedPath);
        if (await roundedFile.exists()) {
          print('✅ [NotificationService] 使用缓存的圆角封面: $roundedPath');
          return roundedPath;
        }
      }
      
      // 如果文件已存在，直接使用
      if (await file.exists()) {
        print('✅ [NotificationService] 使用缓存的封面: $filePath');
        
        // Windows 平台需要创建圆角版本
        if (Platform.isWindows) {
          final roundedPath = await _createRoundedImage(filePath);
          if (roundedPath != null) {
            return roundedPath;
          }
        }
        
        return filePath;
      }
      
      // 下载图片
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 5),
      );
      
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        
        // 如果是 Windows 平台，处理圆角
        if (Platform.isWindows) {
          final roundedPath = await _createRoundedImage(filePath);
          if (roundedPath != null) {
            print('✅ [NotificationService] 圆角封面创建完成: $roundedPath');
            return roundedPath;
          }
        }
        
        print('✅ [NotificationService] 封面下载完成: $filePath');
        return filePath;
      } else {
        print('⚠️ [NotificationService] 封面下载失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [NotificationService] 下载封面失败: $e');
      return null;
    }
  }

  /// 创建圆角图片（用于 Windows 通知）
  Future<String?> _createRoundedImage(String originalPath) async {
    try {
      print('🎨 [NotificationService] 开始创建圆角图片...');
      
      // 读取原始图片
      final originalFile = File(originalPath);
      final imageBytes = await originalFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      // 创建画布
      final size = 200; // 通知图标大小
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;
      
      // 绘制圆角矩形路径
      final radius = size * 0.15; // 圆角半径为边长的 15%
      final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      
      // 裁剪为圆角矩形
      canvas.clipRRect(rrect);
      
      // 绘制图片（缩放并居中）
      final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final dstRect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      canvas.drawImageRect(image, srcRect, dstRect, paint);
      
      // 转换为图片
      final picture = recorder.endRecording();
      final img = await picture.toImage(size, size);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        print('❌ [NotificationService] 无法生成圆角图片数据');
        return null;
      }
      
      // 保存圆角图片
      final roundedPath = originalPath.replaceAll('.jpg', '_rounded.png');
      final roundedFile = File(roundedPath);
      await roundedFile.writeAsBytes(byteData.buffer.asUint8List());
      
      print('✅ [NotificationService] 圆角图片已保存: $roundedPath');
      return roundedPath;
    } catch (e) {
      print('❌ [NotificationService] 创建圆角图片失败: $e');
      return null; // 失败时返回 null，使用原始图片
    }
  }

  /// 清理旧的封面图片缓存
  Future<void> clearCoverCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final notificationDir = Directory(p.join(tempDir.path, 'notification_covers'));
      
      if (await notificationDir.exists()) {
        await notificationDir.delete(recursive: true);
        print('🗑️ [NotificationService] 封面缓存已清理');
        DeveloperModeService().addLog('🗑️ 通知封面缓存已清理');
      }
    } catch (e) {
      print('❌ [NotificationService] 清理封面缓存失败: $e');
    }
  }

  /// 取消特定通知
  Future<void> cancelNotification(int id) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(id: id);
      print('🔔 [NotificationService] 已取消通知 ID: $id');
    } catch (e) {
      print('❌ [NotificationService] 取消通知失败: $e');
    }
  }

  /// 取消所有通知
  Future<void> cancelAll() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
      print('🔔 [NotificationService] 已取消所有通知');
    } catch (e) {
      print('❌ [NotificationService] 取消所有通知失败: $e');
    }
  }

  /// 显示下载完成通知
  /// 带有"打开文件夹"按钮
  Future<void> showDownloadCompleteNotification({
    required String trackName,
    required String artist,
    required String filePath,
    required String folderPath,
    String? coverUrl,
  }) async {
    if (!_isInitialized) await initialize();

    // 下载封面图片（如果提供了URL）
    String? largeIconPath;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      largeIconPath = await _downloadCoverImage(coverUrl);
    }

    // 通知ID使用文件路径的hash，避免重复
    final notificationId = filePath.hashCode.abs() % 100000 + 1000;

    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'cyrene_music_download',
      'Download Notifications',
      channelDescription: 'Notifications for download completion',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Download complete',
      // 添加大图标（专辑封面）
      largeIcon: largeIconPath != null 
          ? FilePathAndroidBitmap(largeIconPath)
          : null,
      styleInformation: largeIconPath != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(largeIconPath),
              largeIcon: FilePathAndroidBitmap(largeIconPath),
              contentTitle: '下载完成',
              summaryText: '$trackName - $artist',
              htmlFormatContentTitle: true,
              htmlFormatSummaryText: true,
              hideExpandedLargeIcon: true,
            )
          : null,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open_folder',
          '打开文件夹',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'dismiss',
          '忽略',
        ),
      ],
    );

    final WindowsNotificationDetails windowsNotificationDetails =
        WindowsNotificationDetails(
      subtitle: '已保存到: $folderPath',
      // Windows 使用 images 参数
      images: largeIconPath != null 
          ? <WindowsImage>[
              WindowsImage(
                Uri.file(largeIconPath, windows: true),
                altText: '专辑封面',
                placement: WindowsImagePlacement.appLogoOverride,
              ),
            ]
          : const <WindowsImage>[],
      actions: <WindowsAction>[
        WindowsAction(
          content: '打开文件夹',
          arguments: 'open_folder:$folderPath',
        ),
        WindowsAction(
          content: '忽略',
          arguments: 'dismiss',
        ),
      ],
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      windows: windowsNotificationDetails,
    );

    try {
      DeveloperModeService().addLog('🔔 显示下载完成通知: $trackName');
      if (largeIconPath != null) {
        DeveloperModeService().addLog('🖼️ 封面图片: $largeIconPath');
      }
      DeveloperModeService().addLog('📁 保存路径: $folderPath');
      
      await _flutterLocalNotificationsPlugin.show(
        id: notificationId,
        title: '下载完成',
        body: '$trackName - $artist',
        notificationDetails: notificationDetails,
        payload: 'download_complete:$folderPath',
      );
      DeveloperModeService().addLog('✅ 下载完成通知已显示');
    } catch (e) {
      DeveloperModeService().addLog('❌ 显示下载完成通知失败: $e');
    }
  }

  /// 打开文件夹（用于通知点击回调）
  static Future<void> openFolder(String folderPath) async {
    try {
      if (Platform.isWindows) {
        // Windows: 使用 explorer 打开文件夹
        await Process.run('explorer', [folderPath]);
        print('📂 [NotificationService] 已打开文件夹: $folderPath');
      } else if (Platform.isAndroid) {
        // Android: 使用 open_filex 或其他方式
        // 这里简单打印日志，实际可以使用 open_filex 包
        print('📂 [NotificationService] Android 打开文件夹: $folderPath');
      } else if (Platform.isMacOS) {
        // macOS: 使用 open 命令
        await Process.run('open', [folderPath]);
        print('📂 [NotificationService] 已打开文件夹: $folderPath');
      } else if (Platform.isLinux) {
        // Linux: 使用 xdg-open
        await Process.run('xdg-open', [folderPath]);
        print('📂 [NotificationService] 已打开文件夹: $folderPath');
      }
    } catch (e) {
      print('❌ [NotificationService] 打开文件夹失败: $e');
    }
  }
}
