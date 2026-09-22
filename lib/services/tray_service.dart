import 'structured_log_service.dart';
import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'player_service.dart';
import 'system_media_service.dart';
import 'persistent_storage_service.dart';
import 'listening_stats_service.dart';

/// 系统托盘服务
/// 仅支持 Windows/macOS/Linux 桌面平台
class TrayService with TrayListener, WindowListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  bool _initialized = false;
  bool _isWindowVisible = true;
  bool _isExiting = false; // 退出标志位

  // 缓存上次菜单状态，避免重复更新
  bool? _lastIsPlaying;
  int? _lastSongId;
  bool? _lastHasSong;

  /// 初始化系统托盘
  Future<void> initialize() async {
    if (_initialized) {
      StructuredLogService.log('⚠️ [TrayService] 托盘已初始化，跳过');
      return;
    }

    // 只在桌面平台初始化
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      StructuredLogService.log('⚠️ [TrayService] 当前平台不支持系统托盘');
      return;
    }

    try {
      StructuredLogService.log('🎯 [TrayService] 开始初始化系统托盘...');

      // 添加监听器
      trayManager.addListener(this);
      windowManager.addListener(this);

      // 设置托盘图标
      await _setTrayIcon();

      // 设置托盘提示文本
      await trayManager.setToolTip('Cyrene Music');

      // 同步初始窗口可见性并确保启动时显示
      try {
        final isVisible = await windowManager.isVisible();
        final isMinimized = await windowManager.isMinimized();
        final isFocused = await windowManager.isFocused();
        _isWindowVisible = isVisible && !isMinimized;

        if (!_isWindowVisible) {
          StructuredLogService.log('🪟 [TrayService] 启动时检测到窗口不可见，尝试显示...');
          await windowManager.show();
          if (!isFocused) {
            await windowManager.focus();
          }
          _isWindowVisible = true;
        }
      } catch (e) {
        StructuredLogService.log('⚠️ [TrayService] 检测/显示窗口失败: $e');
      }

      // 设置右键菜单
      await _setContextMenu();

      _initialized = true;
      StructuredLogService.log('✅ [TrayService] 系统托盘初始化完成');
    } catch (e) {
      StructuredLogService.log('❌ [TrayService] 初始化失败: $e');
    }
  }

  /// 设置托盘图标
  Future<void> _setTrayIcon() async {
    try {
      if (Platform.isWindows) {
        // Windows 使用 .ico 格式
        await trayManager.setIcon('assets/icons/tray_icon.ico');
        StructuredLogService.log('🖼️ [TrayService] Windows 托盘图标已设置');
      } else if (Platform.isMacOS) {
        // macOS 使用 .png 格式
        await trayManager.setIcon('assets/icons/tray_icon.png');
        StructuredLogService.log('🖼️ [TrayService] macOS 托盘图标已设置');
      } else if (Platform.isLinux) {
        // Linux 使用 .png 格式
        await trayManager.setIcon('assets/icons/tray_icon.png');
        StructuredLogService.log('🖼️ [TrayService] Linux 托盘图标已设置');
      }
    } catch (e) {
      StructuredLogService.log('❌ [TrayService] 设置托盘图标失败: $e');
      StructuredLogService.log('💡 [TrayService] 请确保图标文件存在于 assets/icons/ 目录');
    }
  }

  /// 设置托盘右键菜单
  Future<void> _setContextMenu() async {
    final player = PlayerService();

    final menu = Menu(
      items: [
        // 显示/隐藏窗口
        MenuItem(
          key: 'show_window',
          label: _isWindowVisible ? '隐藏窗口' : '显示窗口',
        ),
        MenuItem.separator(),

        // 播放控制
        MenuItem(
          key: 'play_pause',
          label: player.isPlaying ? '暂停' : '播放',
          disabled: player.currentSong == null && player.currentTrack == null,
        ),
        MenuItem(
          key: 'stop',
          label: '停止',
          disabled: player.currentSong == null && player.currentTrack == null,
        ),
        MenuItem.separator(),

        // 当前播放
        MenuItem(
          key: 'now_playing',
          label: _getNowPlayingText(),
          disabled: true,
        ),
        MenuItem.separator(),

        // 测试菜单项（调试用）
        MenuItem(
          key: 'test_exit',
          label: '测试退出',
        ),
        MenuItem.separator(),

        // 退出程序
        MenuItem(
          key: 'exit',
          label: '退出',
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
    StructuredLogService.log('✅ [TrayService] 托盘菜单已更新（${menu.items?.length ?? 0} 项）');
  }

  /// 获取当前播放的歌曲文本
  String _getNowPlayingText() {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    if (song != null) {
      return '♫ ${song.name} - ${song.arName}';
    } else if (track != null) {
      return '♫ ${track.name} - ${track.artists}';
    } else {
      return '当前没有播放';
    }
  }

  /// 更新托盘菜单（智能更新，只在必要时刷新）
  Future<void> updateMenu() async {
    // 如果正在退出或未初始化，不再更新菜单
    if (!_initialized || _isExiting) return;

    final player = PlayerService();
    final currentIsPlaying = player.isPlaying;
    final currentSong = player.currentSong;
    final currentTrack = player.currentTrack;
    // 使用 hashCode 统一处理 int 和 String 类型的 ID
    final currentSongId = currentSong?.id?.hashCode ?? currentTrack?.id?.hashCode;
    final currentHasSong = currentSong != null || currentTrack != null;

    // 检查菜单是否需要更新
    final needsUpdate =
        _lastIsPlaying != currentIsPlaying ||      // 播放状态改变
        _lastSongId != currentSongId ||            // 歌曲切换
        _lastHasSong != currentHasSong;            // 有无歌曲状态改变

    if (!needsUpdate) {
      // 菜单内容未改变，跳过更新
      return;
    }

    // 更新缓存
    _lastIsPlaying = currentIsPlaying;
    _lastSongId = currentSongId;
    _lastHasSong = currentHasSong;

    // 执行菜单更新
    StructuredLogService.log('📋 [TrayService] 菜单内容改变，更新托盘菜单...');
    await _setContextMenu();
  }

  /// 显示窗口
  Future<void> showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      _isWindowVisible = true;
      await updateMenu();
      StructuredLogService.log('👁️ [TrayService] 窗口已显示');
    } catch (e) {
      StructuredLogService.log('❌ [TrayService] 显示窗口失败: $e');
    }
  }

  /// 隐藏窗口
  Future<void> hideWindow() async {
    try {
      await windowManager.hide();
      _isWindowVisible = false;
      await updateMenu();
      StructuredLogService.log('🙈 [TrayService] 窗口已隐藏到托盘');
    } catch (e) {
      StructuredLogService.log('❌ [TrayService] 隐藏窗口失败: $e');
    }
  }

  /// 退出应用
  Future<void> exitApp() async {
    StructuredLogService.log('👋 [TrayService] ========== 开始退出应用 ==========');

    // 立即设置退出标志，阻止任何更新操作
    _isExiting = true;
    StructuredLogService.log('🚫 [TrayService] 已设置退出标志，停止所有更新');

    // 立即移除所有监听器，防止继续接收事件
    try {
      StructuredLogService.log('🔌 [TrayService] 移除托盘和窗口监听器...');
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    } catch (e) {
      StructuredLogService.log('⚠️ [TrayService] 移除监听器失败: $e');
    }

    try {
      // 设置1秒超时，如果清理资源超时则直接强制退出
      await Future.any([
        _cleanupAndExit(),
        Future.delayed(const Duration(seconds: 1)).then((_) {
          StructuredLogService.log('⏰ [TrayService] 清理超时(1秒)，强制退出！');
          exit(0);
        }),
      ]);
    } catch (e) {
      StructuredLogService.log('❌ [TrayService] 退出过程出错: $e');
      // 即使出错也要强制退出
      StructuredLogService.log('🚪 [TrayService] 异常退出，强制终止进程');
      exit(1);
    }
  }

  /// 清理资源并退出
  Future<void> _cleanupAndExit() async {
    try {
      // 0. 同步听歌时长（在退出前保存统计数据）
      StructuredLogService.log('📊 [TrayService] 同步听歌时长...');
      try {
        await ListeningStatsService().syncBeforeExit();
        StructuredLogService.log('✅ [TrayService] 听歌时长已同步');
      } catch (e) {
        StructuredLogService.log('⚠️ [TrayService] 同步听歌时长失败: $e');
      }

      // 1. 先立即保存播放会话，避免后续 forceDispose 取消防抖后丢失最新状态
      StructuredLogService.log('💿 [TrayService] 立即保存播放会话...');
      try {
        await PlayerService().persistSessionImmediately().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () {
            StructuredLogService.log('⚠️ [TrayService] 播放会话保存超时(300ms)');
          },
        );
        StructuredLogService.log('✅ [TrayService] 播放会话已保存');
      } catch (e) {
        StructuredLogService.log('⚠️ [TrayService] 保存播放会话失败: $e');
      }

      // 2. 然后强制备份所有数据（最重要！）
      StructuredLogService.log('💾 [TrayService] 强制备份应用数据...');
      try {
        await PersistentStorageService().forceBackup().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () {
            StructuredLogService.log('⚠️ [TrayService] 数据备份超时(300ms)');
          },
        );
        StructuredLogService.log('✅ [TrayService] 应用数据备份完成');
      } catch (e) {
        StructuredLogService.log('❌ [TrayService] 数据备份失败: $e');
      }

      // 3. 立即清理系统媒体控件（会移除监听器，停止更新）
      StructuredLogService.log('🎛️ [TrayService] 清理系统媒体控件...');
      SystemMediaService().dispose();

      // 等待一小段时间确保监听器完全移除
      await Future.delayed(const Duration(milliseconds: 50));

      // 4. 强制停止并释放播放器资源（不等待）
      StructuredLogService.log('🎵 [TrayService] 停止音频播放...');
      await PlayerService().forceDispose().timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {
          StructuredLogService.log('⚠️ [TrayService] 播放器清理超时(200ms)，跳过');
        },
      );

      // 5. 销毁托盘图标
      StructuredLogService.log('🗑️ [TrayService] 销毁托盘图标...');
      await trayManager.destroy().timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          StructuredLogService.log('⚠️ [TrayService] 托盘销毁超时(100ms)，跳过');
        },
      );

      // 6. 销毁窗口
      StructuredLogService.log('🪟 [TrayService] 销毁窗口...');
      await windowManager.destroy().timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          StructuredLogService.log('⚠️ [TrayService] 窗口销毁超时(100ms)，跳过');
        },
      );

      // 7. 强制退出进程
      StructuredLogService.log('✅ [TrayService] 清理完成，强制退出进程！');
      exit(0);
    } catch (e) {
      StructuredLogService.log('❌ [TrayService] 清理过程出错: $e，强制退出');
      exit(1);
    }
  }

  // ==================== TrayListener 回调 ====================

  @override
  void onTrayIconMouseDown() {
    StructuredLogService.log('🖱️ [TrayService] 托盘图标被点击');
    // 左键单击：显示/隐藏窗口
    if (_isWindowVisible) {
      hideWindow();
    } else {
      showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    StructuredLogService.log('🖱️ [TrayService] 托盘图标右键点击');
    // 手动弹出右键菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    StructuredLogService.log('📋 [TrayService] ========== 菜单项被点击 ==========');
    StructuredLogService.log('📋 [TrayService] 点击的菜单项 key: "${menuItem.key}"');
    StructuredLogService.log('📋 [TrayService] 点击的菜单项 label: "${menuItem.label}"');

    switch (menuItem.key) {
      case 'show_window':
        StructuredLogService.log('🪟 [TrayService] 处理显示/隐藏窗口');
        if (_isWindowVisible) {
          hideWindow();
        } else {
          showWindow();
        }
        break;

      case 'play_pause':
        StructuredLogService.log('⏯️ [TrayService] 处理播放/暂停');
        PlayerService().togglePlayPause();
        updateMenu();
        break;

      case 'stop':
        StructuredLogService.log('⏹️ [TrayService] 处理停止');
        PlayerService().stop();
        updateMenu();
        break;

      case 'test_exit':
        StructuredLogService.log('🧪 [TrayService] 测试退出被点击！');
        StructuredLogService.log('🧪 [TrayService] 3秒后强制退出...');
        Future.delayed(const Duration(seconds: 3), () {
          StructuredLogService.log('🧪 [TrayService] 测试：直接调用 exit(0)');
          exit(0);
        });
        break;

      case 'exit':
        StructuredLogService.log('🚪 [TrayService] 退出菜单被点击！');
        StructuredLogService.log('🚪 [TrayService] 开始执行退出流程...');
        // 使用 Future.microtask 确保异步方法被执行
        Future.microtask(() {
          StructuredLogService.log('🚪 [TrayService] Future.microtask 开始执行');
          exitApp();
        });
        break;

      default:
        StructuredLogService.log('⚠️ [TrayService] 未知的菜单项: ${menuItem.key}');
    }

    StructuredLogService.log('📋 [TrayService] ========== 菜单处理完成 ==========');
  }

  // ==================== WindowListener 回调 ====================

  @override
  void onWindowClose() async {
    StructuredLogService.log('🚪 [TrayService] 窗口关闭事件 - 最小化到托盘');
    // 阻止窗口关闭，改为隐藏到托盘
    // 这样点击窗口的关闭按钮不会退出应用，只会隐藏窗口
    await windowManager.hide();
    _isWindowVisible = false;
    await updateMenu();
  }

  @override
  void onWindowFocus() {
    StructuredLogService.log('👁️ [TrayService] 窗口获得焦点');
    _isWindowVisible = true;
  }

  @override
  void onWindowMinimize() {
    StructuredLogService.log('📉 [TrayService] 窗口最小化');
  }

  @override
  void onWindowMaximize() {
    StructuredLogService.log('📈 [TrayService] 窗口最大化');
  }

  @override
  void onWindowRestore() {
    StructuredLogService.log('↩️ [TrayService] 窗口恢复');
  }

  @override
  void onWindowMoved() {
    // 窗口移动，不需要处理
  }

  @override
  void onWindowResized() {
    // 窗口调整大小，不需要处理
  }

  @override
  void onWindowBlur() {
    // 窗口失去焦点，不需要处理
  }

  @override
  void onWindowEnterFullScreen() {
    StructuredLogService.log('🖥️ [TrayService] 进入全屏');
  }

  @override
  void onWindowLeaveFullScreen() {
    StructuredLogService.log('🖥️ [TrayService] 退出全屏');
  }

  /// 清理资源
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    trayManager.destroy();

    // 清除缓存状态
    _lastIsPlaying = null;
    _lastSongId = null;
    _lastHasSong = null;

    _initialized = false;
    StructuredLogService.log('🗑️ [TrayService] 托盘服务已清理');
  }
}

