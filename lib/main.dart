import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:window_manager/window_manager.dart';
import 'package:cyrene_music/layouts/fluent_main_layout.dart';
import 'package:cyrene_music/layouts/main_layout.dart';
import 'package:cyrene_music/services/android_floating_lyric_service.dart';
import 'package:cyrene_music/services/auto_update_service.dart';
import 'package:cyrene_music/services/cache_service.dart';
import 'package:cyrene_music/services/developer_mode_service.dart';
import 'package:cyrene_music/services/desktop_lyric_service.dart';
import 'package:cyrene_music/services/listening_stats_service.dart';
import 'package:cyrene_music/services/lyric_style_service.dart';
import 'package:cyrene_music/services/lyric_font_service.dart';
import 'package:cyrene_music/services/persistent_storage_service.dart';
import 'package:cyrene_music/services/player_background_service.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:cyrene_music/services/notification_service.dart';
import 'package:cyrene_music/services/playback_resume_service.dart';
import 'package:cyrene_music/services/permission_service.dart';
import 'package:cyrene_music/services/system_media_service.dart';
import 'package:cyrene_music/services/tray_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/services/version_service.dart';
import 'package:cyrene_music/services/mini_player_window_service.dart';
import 'package:cyrene_music/pages/mini_player_window_page.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/services/startup_logger.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:media_kit/media_kit.dart';

// 条件导入 flutter_displaymode（仅 Android）
import 'package:flutter_displaymode/flutter_displaymode.dart' if (dart.library.html) '';

Future<void> main() async {
  final startupLogger = StartupLogger.bootstrapSync(appName: 'CyreneMusic');
  startupLogger.log('main() entered');
  if (startupLogger.filePath != null) {
    print(' [StartupLogger] ${startupLogger.filePath}');
  }

  await runZonedGuarded(() async {
    FlutterError.onError = (details) {
      StartupLogger().log('FlutterError: ${details.exceptionAsString()}\n${details.stack ?? ''}');
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      StartupLogger().log('PlatformDispatcher.onError: $error\n$stack');
      return true;
    };

    void log(String message) {
      StartupLogger().log(message);
      DeveloperModeService().addLog(message);
    }

    Future<T> timed<T>(String name, FutureOr<T> Function() fn) async {
      final sw = Stopwatch()..start();
      log(' $name');
      try {
        final result = await fn();
        log(' $name (${sw.elapsedMilliseconds}ms)');
        return result;
      } catch (e, st) {
        log(' $name: $e');
        StartupLogger().log(' $name stack: $st');
        rethrow;
      }
    }

    await timed('WidgetsFlutterBinding.ensureInitialized', () {
      WidgetsFlutterBinding.ensureInitialized();
    });
  
    await timed('Platform check & initial logs', () {
      log(' 应用启动');
      log(' 平台: ${Platform.operatingSystem}');
    });
  
    if (Platform.isIOS) {
      await timed('SystemChrome.setPreferredOrientations(iOS)', () async {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      });
    }
  
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await timed('MediaKit.ensureInitialized', () {
        try {
          MediaKit.ensureInitialized();
        } catch (e, st) {
          log(' MediaKit.ensureInitialized 失败: $e');
          StartupLogger().log(' MediaKit.ensureInitialized stack: $st');
        }
      });
    }
  
    await timed('PersistentStorageService.initialize', () async {
      await PersistentStorageService().initialize();
    });
    log(' 持久化存储服务已初始化');
  
    await timed('PersistentStorageService.getBackupStats', () {
      final storageStats = PersistentStorageService().getBackupStats();
      log(' 存储统计: ${storageStats['sharedPreferences_keys']} 个键');
      log(' 备份路径: ${storageStats['backup_file_path']}');
    });
  
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await timed('windowManager.ensureInitialized', () async {
        await windowManager.ensureInitialized();
      });

      if (Platform.isWindows) {
        await timed('Window.initialize(Windows)', () async {
          try {
            await Window.initialize();
          } catch (_) {}
        });
      }

      final WindowOptions windowOptions = WindowOptions(
        size: const Size(1320, 880),
        minimumSize: const Size(320, 120),
        center: true,
        backgroundColor: Platform.isWindows ? Colors.transparent : Colors.white,
        skipTaskbar: false,
        titleBarStyle:
            Platform.isWindows ? TitleBarStyle.hidden : TitleBarStyle.normal,
        windowButtonVisibility: !Platform.isWindows,
      );

      await timed('windowManager.waitUntilReadyToShow', () async {
        windowManager.waitUntilReadyToShow(windowOptions, () async {
          log(' windowManager.waitUntilReadyToShow callback entered');
          await timed('windowManager.setTitle', () async {
            await windowManager.setTitle('Cyrene Music');
          });

          await timed('windowManager.setIcon', () async {
            if (Platform.isWindows) {
              await windowManager.setIcon('assets/icons/tray_icon.ico');
            } else if (Platform.isMacOS || Platform.isLinux) {
              await windowManager.setIcon('assets/icons/tray_icon.png');
            }
          });

          await timed('windowManager.show', () async {
            await windowManager.show();
          });

          await timed('windowManager.focus', () async {
            await windowManager.focus();
          });

          await timed('windowManager.setPreventClose(true)', () async {
            await windowManager.setPreventClose(true);
          });

          log(' [Main] 窗口已显示，关闭按钮将最小化到托盘');
        });
      });
    }
  
    await timed('UrlService.initialize', () async {
      await UrlService().initialize();
    });
    log(' URL 服务已初始化');
  
    await timed('VersionService.initialize', () async {
      await VersionService().initialize();
    });
    log(' 版本服务已初始化');

    await timed('AutoUpdateService.initialize', () async {
      await AutoUpdateService().initialize();
    });
    log(' 自动更新服务已初始化');
  
    await timed('CacheService.initialize', () async {
      await CacheService().initialize();
    });
    log(' 缓存服务已初始化');
  
    await timed('PlayerBackgroundService.initialize', () async {
      await PlayerBackgroundService().initialize();
    });
    log(' 播放器背景服务已初始化');
  
    await timed('PlayerService.initialize', () async {
      await PlayerService().initialize();
    });
    log(' 播放器服务已初始化');
  
    await timed('LyricStyleService.initialize', () async {
      await LyricStyleService().initialize();
    });
    log(' 歌词样式服务已初始化');
  
    await timed('LyricFontService.initialize', () async {
      await LyricFontService().initialize();
    });
    log(' 歌词字体服务已初始化');
  
    if (Platform.isAndroid) {
      await timed('Android edgeToEdge + overlays', () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
        ));
        log(' 已启用边到边模式');
      });

      await timed('PermissionService.requestNotificationPermission', () async {
        final hasPermission = await PermissionService().requestNotificationPermission();
        if (hasPermission) {
          log(' 通知权限已授予');
        } else {
          log(' 通知权限未授予，媒体通知可能无法显示');
        }
      });

      await timed('FlutterDisplayMode.setHighRefreshRate', () async {
        try {
          await FlutterDisplayMode.setHighRefreshRate();
          final activeMode = await FlutterDisplayMode.active;
          log(
              ' 显示模式: ${activeMode.width}x${activeMode.height} @${activeMode.refreshRate.toStringAsFixed(0)}Hz');
          print(
              ' [DisplayMode] 已启用高刷新率: ${activeMode.refreshRate.toStringAsFixed(0)}Hz');
        } catch (e) {
          log(' 高刷新率设置失败: $e');
          print(' [DisplayMode] 设置高刷新率失败: $e');
        }
      });
    }
  
    await timed('SystemMediaService.initialize', () async {
      await SystemMediaService().initialize();
    });
    log(' 系统媒体服务已初始化');
  
    await timed('TrayService.initialize', () async {
      await TrayService().initialize();
    });
    log(' 系统托盘已初始化');
  
    await timed('ListeningStatsService.initialize', () {
      ListeningStatsService().initialize();
    });
    log(' 听歌统计服务已初始化');
  
    await timed('NotificationService.initialize', () async {
      await NotificationService().initialize();
    });
  
    if (Platform.isWindows) {
      await timed('DesktopLyricService.initialize(Windows)', () async {
        await DesktopLyricService().initialize();
      });
      log(' 桌面歌词服务已初始化');
    }
  
    if (Platform.isAndroid) {
      await timed('AndroidFloatingLyricService.initialize(Android)', () async {
        await AndroidFloatingLyricService().initialize();
      });
      log(' Android悬浮歌词服务已初始化');
    }
  
    print(' [Main] 将在2秒后检查播放恢复状态...');
    log(' 将在2秒后检查播放恢复状态...');

    Future.delayed(const Duration(seconds: 2), () {
      print(' [Main] 开始检查播放恢复状态...');
      log(' 开始检查播放恢复状态...');

      PlaybackResumeService().checkAndShowResumeNotification().then((_) {
        print(' [Main] 播放恢复检查完成');
        log(' 播放恢复检查完成');
      }).catchError((e, st) {
        print(' [Main] 播放恢复检查失败: $e');
        log(' 播放恢复检查失败: $e');
        StartupLogger().log(' 播放恢复检查失败 stack: $st');
      });
    });

    await timed('runApp(MyApp)', () {
      runApp(const MyApp());
    });
  
    if (Platform.isWindows) {
      await timed('doWhenWindowReady(Windows)', () {
        doWhenWindowReady(() {
          const initialSize = Size(1320, 880);
          const minSize = Size(160, 60);

          appWindow.minSize = minSize;
          appWindow.size = initialSize;
          appWindow.alignment = Alignment.center;
          appWindow.title = 'Cyrene Music';
          appWindow.show();
        });
      });
    }
  }, (error, stack) {
    StartupLogger().log('runZonedGuarded: $error\n$stack');
  });
 }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return AnimatedBuilder(
      animation: themeManager,
      builder: (context, _) {
        final lightTheme = themeManager.buildThemeData(Brightness.light);
        final darkTheme = themeManager.buildThemeData(Brightness.dark);

        final useFluentLayout = Platform.isWindows && themeManager.isFluentFramework;
        final useCupertinoLayout = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;

        if (useFluentLayout) {
          return AnimatedBuilder(
            animation: MiniPlayerWindowService(),
            builder: (context, _) {
              final isMiniMode = MiniPlayerWindowService().isMiniMode;
              return fluent.FluentApp(
                title: 'Cyrene Music',
                debugShowCheckedModeBanner: false,
                theme: themeManager.buildFluentThemeData(Brightness.light),
                darkTheme: themeManager.buildFluentThemeData(Brightness.dark),
                themeMode: _mapMaterialThemeMode(themeManager.themeMode),
                scrollBehavior: const _FluentScrollBehavior(),
                home: isMiniMode ? const MiniPlayerWindowPage() : const FluentMainLayout(),
              );
            },
          );
        }

        // 移动端 Cupertino 风格
        if (useCupertinoLayout) {
          final cupertinoTheme = themeManager.buildCupertinoThemeData(
            themeManager.themeMode == ThemeMode.dark 
                ? Brightness.dark 
                : (themeManager.themeMode == ThemeMode.system 
                    ? WidgetsBinding.instance.platformDispatcher.platformBrightness 
                    : Brightness.light),
          );
          
          // 使用 MaterialApp 包裹 CupertinoTheme 以保持 Navigator 等功能
          return MaterialApp(
            title: 'Cyrene Music',
            debugShowCheckedModeBanner: false,
            theme: lightTheme.copyWith(
              cupertinoOverrideTheme: themeManager.buildCupertinoThemeData(Brightness.light),
            ),
            darkTheme: darkTheme.copyWith(
              cupertinoOverrideTheme: themeManager.buildCupertinoThemeData(Brightness.dark),
            ),
            themeMode: themeManager.themeMode,
            builder: (context, child) {
              return CupertinoTheme(
                data: cupertinoTheme,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const MainLayout(),
          );
        }

        return MaterialApp(
          title: 'Cyrene Music',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeManager.themeMode,
          home: Platform.isWindows
            ? _WindowsRoundedContainer(child: const MainLayout())
            : const MainLayout(),
        );
      },
    );
  }
}

fluent.ThemeMode _mapMaterialThemeMode(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return fluent.ThemeMode.light;
    case ThemeMode.dark:
      return fluent.ThemeMode.dark;
    case ThemeMode.system:
      return fluent.ThemeMode.system;
  }
}
class _FluentScrollBehavior extends MaterialScrollBehavior {
  const _FluentScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

/// Windows 圆角窗口容器
class _WindowsRoundedContainer extends StatefulWidget {
  final Widget child;
  
  const _WindowsRoundedContainer({required this.child});

  @override
  State<_WindowsRoundedContainer> createState() => _WindowsRoundedContainerState();
}

class _WindowsRoundedContainerState extends State<_WindowsRoundedContainer> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximizedState() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = isMaximized;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 最大化时无边距和圆角，正常时有边距和圆角
    return Container(
      padding: _isMaximized ? EdgeInsets.zero : const EdgeInsets.all(8.0),
      color: Theme.of(context).colorScheme.background,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: _isMaximized ? BorderRadius.zero : BorderRadius.circular(12),
          // 移除阴影效果
        ),
        child: ClipRRect(
          borderRadius: _isMaximized ? BorderRadius.zero : BorderRadius.circular(12),
          child: widget.child,
        ),
      ),
    );
  }
}