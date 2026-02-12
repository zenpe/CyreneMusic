import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:window_manager/window_manager.dart';
import 'package:cyrene_music/layouts/fluent_main_layout.dart';
import 'package:cyrene_music/layouts/main_layout.dart';
import 'package:cyrene_music/services/android_floating_lyric_service.dart';
import 'package:cyrene_music/services/announcement_service.dart';
import 'package:cyrene_music/services/auto_update_service.dart';
import 'package:cyrene_music/services/cache_service.dart';
import 'package:cyrene_music/services/developer_mode_service.dart';
import 'package:cyrene_music/services/app_settings_service.dart';
import 'package:cyrene_music/services/desktop_lyric_service.dart';
import 'package:cyrene_music/services/listening_stats_service.dart';
import 'package:cyrene_music/services/lyric_style_service.dart';
import 'package:cyrene_music/services/lyric_font_service.dart';
import 'package:cyrene_music/services/persistent_storage_service.dart';
import 'package:cyrene_music/services/navidrome_session_service.dart';
import 'package:cyrene_music/services/player_background_service.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:cyrene_music/services/notification_service.dart';
import 'package:cyrene_music/services/playback_resume_service.dart';
import 'package:cyrene_music/services/permission_service.dart';
import 'package:cyrene_music/services/startup_queue_loader_service.dart';
import 'package:cyrene_music/services/system_media_service.dart';
import 'package:cyrene_music/services/tray_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/services/audio_source_service.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/version_service.dart';
import 'package:cyrene_music/services/mini_player_window_service.dart';
import 'package:cyrene_music/services/local_library_service.dart';
import 'package:cyrene_music/pages/mini_player_window_page.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/services/startup_logger.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:media_kit/media_kit.dart';
import 'package:cyrene_music/pages/settings_page/audio_source_settings.dart';
import 'package:cyrene_music/pages/mobile_setup_page.dart';
import 'package:cyrene_music/pages/mobile_app_gate.dart';
import 'package:cyrene_music/pages/desktop_app_gate.dart';

// 条件导入 flutter_displaymode（仅 Android）
import 'package:flutter_displaymode/flutter_displaymode.dart'
    if (dart.library.html) '';

Future<void> main() async {
  final startupLogger = StartupLogger.bootstrapSync(appName: 'CyreneMusic');
  startupLogger.log('main() entered');
  if (startupLogger.filePath != null && kDebugMode) {
    print(' [StartupLogger] ${startupLogger.filePath}');
  }

  await runZonedGuarded(
    () async {
      FlutterError.onError = (details) {
        StartupLogger().log(
          'FlutterError: ${details.exceptionAsString()}\n${details.stack ?? ''}',
        );
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

      if (Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isAndroid) {
        await timed('MediaKit.ensureInitialized', () {
          try {
            MediaKit.ensureInitialized();
          } catch (e, st) {
            log(' MediaKit.ensureInitialized 失败: $e');
            StartupLogger().log(' MediaKit.ensureInitialized stack: $st');
          }
        });
      }

      // ── 第 1 批：基础服务（串行，有依赖关系） ──
      await timed('PersistentStorageService.initialize', () async {
        await PersistentStorageService().initialize();
      });
      log(' 持久化存储服务已初始化');

      // Navidrome 会话服务初始化（依赖 PersistentStorageService）
      await timed('NavidromeSessionService.initialize', () async {
        await NavidromeSessionService().initialize();
      });
      log(' Navidrome 会话服务已初始化');

      await timed('PersistentStorageService.getBackupStats', () {
        final storageStats = PersistentStorageService().getBackupStats();
        log(' 存储统计: ${storageStats['sharedPreferences_keys']} 个键');
        log(' 备份路径: ${storageStats['backup_file_path']}');
      });

      // WindowManager 初始化（平台相关 UI 操作，保持原有位置）
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
          backgroundColor: Platform.isWindows
              ? Colors.transparent
              : Colors.white,
          skipTaskbar: false,
          titleBarStyle: Platform.isWindows
              ? TitleBarStyle.hidden
              : TitleBarStyle.normal,
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

      // Android 特有的 edge-to-edge
      if (Platform.isAndroid) {
        await timed('Android edgeToEdge + overlays', () {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setSystemUIOverlayStyle(
            const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
            ),
          );
          log(' 已启用边到边模式');
        });
      }

      // ── 第 2 批：无互相依赖的服务（并行） ──
      await timed(
        'Batch 2: parallel services',
        () => Future.wait([
          timed('DeveloperModeService.initialize', () async {
            await DeveloperModeService().initialize();
            log('✅ 开发者模式服务已初始化');
          }),
          timed('AppSettingsService.initialize', () async {
            await AppSettingsService().initialize();
            log(' 应用设置服务已初始化');
          }),
          timed('UrlService.initialize', () async {
            await UrlService().initialize();
            log('✅ URL 服务已初始化');
          }),
          timed('LocalLibraryService.init', () async {
            await LocalLibraryService().init();
            log(' 本地音乐库服务已初始化');
          }),
          timed('LyricStyleService.initialize', () async {
            await LyricStyleService().initialize();
            log(' 歌词样式服务已初始化');
          }),
          timed('LyricFontService.initialize', () async {
            await LyricFontService().initialize();
            log(' 歌词字体服务已初始化');
          }),
          timed('PlayerBackgroundService.initialize', () async {
            await PlayerBackgroundService().initialize();
            log(' 播放器背景服务已初始化');
          }),
          timed('AudioSourceService.initialize', () async {
            await AudioSourceService().initialize();
            log('✅ 音源服务已初始化');
          }),
        ]),
      );

      // ── 第 3 批：依赖第 1-2 批的服务（并行） ──
      await timed(
        'Batch 3: parallel services',
        () => Future.wait([
          timed('VersionService.initialize', () async {
            await VersionService().initialize();
            log(' 版本服务已初始化');
          }),
          timed('AutoUpdateService.initialize', () async {
            await AutoUpdateService().initialize();
            log(' 自动更新服务已初始化');
          }),
          timed('ListeningStatsService.initialize', () async {
            ListeningStatsService().initialize();
            log(' 听歌统计服务已初始化');
          }),
          timed('NotificationService.initialize', () async {
            await NotificationService().initialize();
          }),
        ]),
      );

      // ── 第 4 批：串行，有依赖关系 ──
      await timed('PlayerService.initialize', () async {
        await PlayerService().initialize();
      });
      log(' 播放器服务已初始化');

      await timed('SystemMediaService.initialize', () async {
        await SystemMediaService().initialize();
      });
      log(' 系统媒体服务已初始化');

      await timed('TrayService.initialize', () async {
        await TrayService().initialize();
      });
      log(' 系统托盘已初始化');

      // ── 第 5 批：平台相关服务（放最后） ──
      if (Platform.isWindows) {
        await timed('DesktopLyricService.initialize(Windows)', () async {
          await DesktopLyricService().initialize();
        });
        log(' 桌面歌词服务已初始化');
      }

      if (Platform.isAndroid) {
        await timed(
          'AndroidFloatingLyricService.initialize(Android)',
          () async {
            await AndroidFloatingLyricService().initialize();
          },
        );
        log(' Android悬浮歌词服务已初始化');
      }

      print(' [Main] 将在1秒后加载启动播放队列...');
      log(' 将在1秒后加载启动播放队列...');
      Future.delayed(const Duration(seconds: 1), () {
        StartupQueueLoaderService()
            .loadStartupQueueIfNeeded()
            .then((_) {
              print(' [Main] 启动播放队列加载完成');
              log(' 启动播放队列加载完成');
            })
            .catchError((e, st) {
              print(' [Main] 启动播放队列加载失败: $e');
              log(' 启动播放队列加载失败: $e');
              StartupLogger().log(' 启动播放队列加载失败 stack: $st');
            });
      });

      print(' [Main] 将在2秒后检查播放恢复状态...');
      log(' 将在2秒后检查播放恢复状态...');

      Future.delayed(const Duration(seconds: 2), () {
        print(' [Main] 开始检查播放恢复状态...');
        log(' 开始检查播放恢复状态...');

        PlaybackResumeService()
            .checkAndShowResumeNotification()
            .then((_) {
              print(' [Main] 播放恢复检查完成');
              log(' 播放恢复检查完成');
            })
            .catchError((e, st) {
              print(' [Main] 播放恢复检查失败: $e');
              log(' 播放恢复检查失败: $e');
              StartupLogger().log(' 播放恢复检查失败 stack: $st');
            });
      });

      await timed('runApp(MyApp)', () {
        runApp(const MyApp());
      });

      // P0: 权限请求放到 runApp 之后
      if (Platform.isAndroid) {
        Future.microtask(() async {
          await timed(
            'PermissionService.requestNotificationPermission',
            () async {
              final hasPermission = await PermissionService()
                  .requestNotificationPermission();
              if (hasPermission) {
                log(' 通知权限已授予');
              } else {
                log(' 通知权限未授予，媒体通知可能无法显示');
              }
            },
          );
        });
      }

      // P0: 公告请求延迟到 runApp 之后，避免阻塞首帧
      Future.microtask(() async {
        await timed('AnnouncementService.initialize', () async {
          await AnnouncementService().initialize();
          log(' 公告服务已初始化');
        });
      });

      // P2: 缓存服务初始化延迟到 runApp 之后
      Future.microtask(() async {
        await timed('CacheService.initialize', () async {
          await CacheService().initialize();
          log(' 缓存服务已初始化');
        });
      });
    },
    (error, stack) {
      StartupLogger().log('runZonedGuarded: $error\n$stack');
    },
    zoneSpecification: kReleaseMode
        ? ZoneSpecification(print: (self, parent, zone, line) {})
        : null,
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // 全局 Navigator Key（用于在任何地方显示对话框）
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // 延迟设置高刷新率和回调，确保 Navigator 和 Activity 已经初始化
    Future.delayed(const Duration(milliseconds: 500), () {
      _setupAudioSourceCallback();
      _setupHighRefreshRate();
    });
  }

  Future<void> _setupHighRefreshRate() async {
    if (!Platform.isAndroid) return;

    try {
      // 获取所有可用的模式
      final modes = await FlutterDisplayMode.supported;
      if (modes.isNotEmpty) {
        print(' [DisplayMode] 发现 ${modes.length} 个可用模式:');
        for (var mode in modes) {
          print(
            '   - ID: ${mode.id}, ${mode.width}x${mode.height} @${mode.refreshRate.toStringAsFixed(0)}Hz',
          );
        }

        // 挑选最高刷新率模式
        final optimalMode = modes.reduce((curr, next) {
          if (next.refreshRate > curr.refreshRate) return next;
          if (next.refreshRate == curr.refreshRate &&
              (next.width * next.height) > (curr.width * curr.height))
            return next;
          return curr;
        });

        print(
          ' [DisplayMode] 尝试设置最高刷新率模式: ID: ${optimalMode.id}, ${optimalMode.width}x${optimalMode.height} @${optimalMode.refreshRate.toStringAsFixed(0)}Hz',
        );
        await FlutterDisplayMode.setPreferredMode(optimalMode);
      } else {
        await FlutterDisplayMode.setHighRefreshRate();
      }

      final activeMode = await FlutterDisplayMode.active;
      print(
        ' [DisplayMode] 最终激活模式: ${activeMode.width}x${activeMode.height} @${activeMode.refreshRate.toStringAsFixed(0)}Hz',
      );
    } catch (e) {
      print(' [DisplayMode] 设置高刷新率失败: $e');
    }
  }

  void _setupAudioSourceCallback() {
    PlayerService().onAudioSourceNotConfigured = () {
      print('🔔 [MyApp] 音源未配置回调被触发');
      // 优先使用 GlobalContextHolder（包含正确的 Localizations）
      final globalContext = GlobalContextHolder.context;
      final navigatorContext = MyApp.navigatorKey.currentContext;
      final contextToUse = globalContext ?? navigatorContext;

      if (contextToUse != null) {
        print(
          '🔔 [MyApp] 使用 ${globalContext != null ? "GlobalContextHolder" : "navigatorKey"} context 显示弹窗',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showAudioSourceNotConfiguredDialog(contextToUse);
        });
      } else {
        print('⚠️ [MyApp] 无法获取有效的 context');
      }
    };
    print('✅ [MyApp] 音源未配置回调已设置');
  }

  @override
  void dispose() {
    PlayerService().onAudioSourceNotConfigured = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return AnimatedBuilder(
      animation: Listenable.merge([themeManager, DeveloperModeService()]),
      builder: (context, _) {
        final lightTheme = themeManager.buildThemeData(Brightness.light);
        final darkTheme = themeManager.buildThemeData(Brightness.dark);

        final useFluentLayout = themeManager.isDesktopFluentUI;
        final useCupertinoLayout =
            (Platform.isIOS || Platform.isAndroid) &&
            themeManager.isCupertinoFramework;

        if (useFluentLayout) {
          return AnimatedBuilder(
            animation: MiniPlayerWindowService(),
            builder: (context, _) {
              final isMiniMode = MiniPlayerWindowService().isMiniMode;
              return fluent.FluentApp(
                title: 'Cyrene Music',
                debugShowCheckedModeBanner: false,
                showPerformanceOverlay:
                    DeveloperModeService().showPerformanceOverlay,
                theme: themeManager.buildFluentThemeData(Brightness.light),
                darkTheme: themeManager.buildFluentThemeData(Brightness.dark),
                themeMode: _mapMaterialThemeMode(themeManager.themeMode),
                scrollBehavior: const _FluentScrollBehavior(),
                builder: (context, child) {
                  // 保存 Navigator context 供全局使用
                  // 使用 FToastBuilder 以确保 Toast 能够正确初始化
                  final ftoastBuilder = FToastBuilder();
                  // 添加 ScaffoldMessenger 支持 SnackBar（即使在 Fluent UI 中）
                  return ScaffoldMessenger(
                    child: ftoastBuilder(
                      context,
                      Overlay(
                        initialEntries: [
                          OverlayEntry(
                            builder: (innerContext) {
                              GlobalContextHolder._context = innerContext;
                              return child!;
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                home: isMiniMode
                    ? const MiniPlayerWindowPage()
                    : const DesktopAppGate(),
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
                      ? WidgetsBinding
                            .instance
                            .platformDispatcher
                            .platformBrightness
                      : Brightness.light),
          );

          // 使用 MaterialApp 包裹 CupertinoTheme 以保持 Navigator 等功能
          // MobileAppGate 内部处理状态切换，避免重建 MaterialApp
          return MaterialApp(
            title: 'Cyrene Music',
            debugShowCheckedModeBanner: false,
            showPerformanceOverlay:
                DeveloperModeService().showPerformanceOverlay,
            navigatorKey: MyApp.navigatorKey,
            theme: lightTheme.copyWith(
              cupertinoOverrideTheme: themeManager.buildCupertinoThemeData(
                Brightness.light,
              ),
            ),
            darkTheme: darkTheme.copyWith(
              cupertinoOverrideTheme: themeManager.buildCupertinoThemeData(
                Brightness.dark,
              ),
            ),
            themeMode: themeManager.themeMode,
            builder: (context, child) {
              final ftoastBuilder = FToastBuilder();
              return CupertinoTheme(
                data: cupertinoTheme,
                child: ftoastBuilder(
                  context,
                  Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (innerContext) {
                          GlobalContextHolder._context = innerContext;
                          return child!;
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            home: const MobileAppGate(),
          );
        }

        // 非 Cupertino 的 Material 布局
        // 移动端使用 MobileAppGate 处理状态切换
        if (Platform.isAndroid || Platform.isIOS) {
          return MaterialApp(
            title: 'Cyrene Music',
            debugShowCheckedModeBanner: false,
            navigatorKey: MyApp.navigatorKey,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: themeManager.themeMode,
            builder: (context, child) {
              final ftoastBuilder = FToastBuilder();
              return ftoastBuilder(
                context,
                Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (innerContext) {
                        GlobalContextHolder._context = innerContext;
                        return child!;
                      },
                    ),
                  ],
                ),
              );
            },
            home: const MobileAppGate(),
          );
        }

        // 桌面端直接进入主布局
        return MaterialApp(
          title: 'Cyrene Music',
          debugShowCheckedModeBanner: false,
          showPerformanceOverlay: DeveloperModeService().showPerformanceOverlay,
          navigatorKey: MyApp.navigatorKey,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeManager.themeMode,
          builder: (context, child) {
            final ftoastBuilder = FToastBuilder();
            final content = ftoastBuilder(
              context,
              Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (innerContext) {
                      GlobalContextHolder._context = innerContext;
                      return child!;
                    },
                  ),
                ],
              ),
            );

            // 桌面端添加刷新率助推器
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
              return RefreshRateBooster(child: content);
            }
            return content;
          },
          home: Platform.isWindows
              ? _WindowsRoundedContainer(child: const MainLayout())
              : const MainLayout(),
        );
      },
    );
  }
}

/// 全局 Context 保存器
class GlobalContextHolder {
  static BuildContext? _context;
  static BuildContext? get context => _context;
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
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Windows 圆角窗口容器
class _WindowsRoundedContainer extends StatefulWidget {
  final Widget child;

  const _WindowsRoundedContainer({required this.child});

  @override
  State<_WindowsRoundedContainer> createState() =>
      _WindowsRoundedContainerState();
}

class _WindowsRoundedContainerState extends State<_WindowsRoundedContainer>
    with WindowListener {
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
          borderRadius: _isMaximized
              ? BorderRadius.zero
              : BorderRadius.circular(12),
          // 移除阴影效果
        ),
        child: ClipRRect(
          borderRadius: _isMaximized
              ? BorderRadius.zero
              : BorderRadius.circular(12),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 显示音源未配置对话框
void showAudioSourceNotConfiguredDialog(BuildContext context) {
  final themeManager = ThemeManager();
  final isFluent = themeManager.isDesktopFluentUI;
  final isCupertino =
      (Platform.isIOS || Platform.isAndroid) &&
      themeManager.isCupertinoFramework;
  final isNavidromeActive = AudioSourceService().isNavidromeActive;
  final title = isNavidromeActive ? 'Navidrome 未配置' : '音源失效';
  final content = isNavidromeActive
      ? '当前 Navidrome 配置似乎已失效或未填写，请重新配置。'
      : '当前音源配置似乎已失效或无法连接，请重新配置音源。';
  final targetPage = isNavidromeActive
      ? const AudioSourceSettings(openNavidromeSettings: true)
      : const AudioSourceSettings();

  if (isFluent) {
    fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            fluent.FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => targetPage),
                );
              },
              child: const Text('去配置'),
            ),
          ],
        );
      },
    );
  } else if (isCupertino) {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => targetPage),
                );
              },
              child: const Text('去配置'),
            ),
          ],
        );
      },
    );
  } else {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => targetPage),
                );
              },
              child: const Text('去配置'),
            ),
          ],
        );
      },
    );
  }
}

/// 刷新率助推器 (Keep-Alive Component)
/// 在桌面端通过一个极低负载的动画，诱导 Flutter 引擎始终以显示器最高频率运行
class RefreshRateBooster extends StatefulWidget {
  final Widget child;
  const RefreshRateBooster({super.key, required this.child});

  @override
  State<RefreshRateBooster> createState() => _RefreshRateBoosterState();
}

class _RefreshRateBoosterState extends State<RefreshRateBooster>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 创建一个极其轻量级的动画
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(); // 永远重复
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 渲染一个几乎不可见（不占像素，不重绘复杂区域）的动画
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // 动态改变透明度，强制引擎认为每一帧都是“脏的”，从而请求显示器最高刷新率所需的 VSync
            // 0.001 - 0.002 之间的微小变化足以触发重绘，但几乎不可见
            return Opacity(
              opacity: 0.001 + (_controller.value * 0.001),
              child: const SizedBox(width: 1, height: 1),
            );
          },
        ),
      ],
    );
  }
}
