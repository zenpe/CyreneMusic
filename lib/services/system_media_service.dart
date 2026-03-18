import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'player_service.dart';
import 'tray_service.dart';
import 'audio_handler_service.dart';
import 'native_smtc_service.dart';

/// 系统媒体控件服务
/// 用于在 Windows 和 Android 平台上集成原生媒体控件
class SystemMediaService {
  static final SystemMediaService _instance = SystemMediaService._internal();
  factory SystemMediaService() => _instance;
  SystemMediaService._internal();

  NativeSmtcService? _nativeSmtc;
  CyreneAudioHandler? _audioHandler;  // Android 媒体处理器
  bool _initialized = false;
  bool _isDisposed = false; // 是否已释放
  bool _mobileInitialized = false; // 移动端是否已初始化（延迟初始化）

  // 缓存上次更新的信息，避免重复更新
  int? _lastSongId;  // 使用 hashCode 作为唯一标识
  PlayerState? _lastPlayerState;

  /// 初始化系统媒体控件
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (Platform.isWindows) {
        await _initializeWindows();
      } else if (Platform.isAndroid || Platform.isIOS) {
        // 🔧 关键修复：移动端不在启动时初始化 audio_service，避免音频系统初始化导致的杂音
        // audio_service 将在第一次播放时才初始化（见 _ensureMobileInitialized 方法）
        print('📱 [SystemMediaService] 移动端 audio_service 将在首次播放时初始化');
      }

      // 监听播放器状态变化
      PlayerService().addListener(_onPlayerStateChanged);

      _initialized = true;
      print('🎵 [SystemMediaService] 系统媒体控件初始化完成');
    } catch (e) {
      print('❌ [SystemMediaService] 初始化失败: $e');
    }
  }

  /// 确保移动端 audio_service 已初始化（首次播放时或手动同步小部件时调用）
  Future<void> ensureMobileInitialized() async {
    if (_mobileInitialized || !Platform.isAndroid && !Platform.isIOS) return;

    await _initializeMobile();
    _mobileInitialized = true;
  }

  /// 初始化 Windows 媒体控件 (SMTC)
  Future<void> _initializeWindows() async {
    try {
      _nativeSmtc = NativeSmtcService();
      await _nativeSmtc!.initialize();

      // 监听 SMTC 按钮事件
      _nativeSmtc!.buttonPressStream.listen((button) {
        _handleNativeButtonPress(button);
      });

      // 初始状态设置为停止
      await _nativeSmtc!.updatePlaybackStatus(SmtcPlaybackStatus.stopped);
      
      print('✅ [SystemMediaService] Windows SMTC 初始化成功');
    } catch (e) {
      print('❌ [SystemMediaService] Windows SMTC 初始化失败: $e');
    }
  }

  /// 初始化移动端媒体控件 (Android/iOS)
  Future<void> _initializeMobile() async {
    try {
      final platformName = Platform.isAndroid ? 'Android' : 'iOS';
      print('📱 [SystemMediaService] 开始初始化 $platformName audio_service...');
      
      // 初始化 audio_service 并创建 AudioHandler
      // 根据文档：androidStopForegroundOnPause = false 时，androidNotificationOngoing 必须也为 false
      // 这样可以避免 Android 12+ 的 ForegroundServiceStartNotAllowedException
      _audioHandler = await AudioService.init(
        builder: () => CyreneAudioHandler(),
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.cyrene.music.channel.audio',
          androidNotificationChannelName: 'Cyrene Music',
          androidNotificationOngoing: false, // 恢复为 false 以符合 audio_service 的断言限制 (androidStopForegroundOnPause 为 false 时必须为 false)
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false, // 保持核心逻辑：暂停时不停止前台服务，确保应用在 Android 12+ 后台存活
        ),
      );
      
      if (_audioHandler != null) {
        // 🔧 关键修复：强制启用媒体按钮（包括蓝牙控制）- 仅 Android
        // 根据 audio_service 文档，这需要在初始化后调用
        if (Platform.isAndroid) {
          await AudioService.androidForceEnableMediaButtons();
          print('✅ [SystemMediaService] 已强制启用媒体按钮（蓝牙控制）');
        }
        
        print('✅ [SystemMediaService] $platformName audio_service 初始化成功');
        print('   AudioHandler 类型: ${_audioHandler.runtimeType}');
        if (Platform.isAndroid) {
          print('   通知渠道 ID: com.cyrene.music.channel.audio');
          print('   ⚠️ 如果通知未显示，请检查：');
          print('      1. 是否授予了通知权限（Android 13+）');
          print('      2. 是否播放了歌曲触发状态更新');
          print('      3. 查看 AudioHandler 日志确认状态是否更新');
        }
      } else {
        print('❌ [SystemMediaService] AudioHandler 为 null');
      }
    } catch (e, stackTrace) {
      print('❌ [SystemMediaService] 移动端 audio_service 初始化失败: $e');
      print('   堆栈跟踪: $stackTrace');
    }
  }

  /// 处理原生SMTC按钮事件
  void _handleNativeButtonPress(SmtcButton button) {
    final player = PlayerService();
    
    switch (button) {
      case SmtcButton.play:
        print('▶️ [SystemMediaService] 系统媒体控件: 播放');
        player.resume();
        break;
      case SmtcButton.pause:
        print('⏸️ [SystemMediaService] 系统媒体控件: 暂停');
        player.pause();
        break;
      case SmtcButton.stop:
        print('⏹️ [SystemMediaService] 系统媒体控件: 停止');
        player.stop();
        break;
      case SmtcButton.next:
        print('⏭️ [SystemMediaService] 系统媒体控件: 下一曲');
        player.playNext();
        break;
      case SmtcButton.previous:
        print('⏮️ [SystemMediaService] 系统媒体控件: 上一曲');
        player.playPrevious();
        break;
      default:
        break;
    }
  }

  /// 手动更新移动端小部件（供实验室功能开关调用）
  Future<void> updateWidget() async {
    if (Platform.isAndroid) {
      if (!_mobileInitialized) {
        await ensureMobileInitialized();
      }
      if (_audioHandler != null) {
        _audioHandler!.refreshWidget();
      }
    }
  }

  /// 监听播放器状态变化，同步到系统媒体控件
  void _onPlayerStateChanged() {
    // 如果已释放或未初始化，不再处理
    if (!_initialized || _isDisposed) {
      print('⚠️ [SystemMediaService] 已释放，跳过状态更新');
      return;
    }

    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    // 🔧 关键修复：在首次播放时才初始化移动端 audio_service
    if ((Platform.isAndroid || Platform.isIOS) && !_mobileInitialized) {
      // 只有在真正开始播放时才初始化（loading 或 playing 状态）
      if (player.state == PlayerState.loading || player.state == PlayerState.playing) {
        print('🎵 [SystemMediaService] 检测到首次播放，初始化 audio_service...');
        ensureMobileInitialized().then((_) {
          print('✅ [SystemMediaService] audio_service 初始化完成，继续更新状态');
          // 初始化完成后，再次触发状态更新
          _onPlayerStateChanged();
        }).catchError((e) {
          print('❌ [SystemMediaService] audio_service 初始化失败: $e');
        });
        return; // 等待初始化完成
      } else {
        // 如果还没开始播放，不需要初始化
        return;
      }
    }

    if (Platform.isWindows && _nativeSmtc != null) {
      _updateWindowsMedia(player, song, track);
    }
    // Android 平台的媒体通知由 AudioHandler 自动处理，无需在此手动更新

    // 同时更新系统托盘菜单（updateMenu 内部已有智能检测，不会频繁更新）
    if (!_isDisposed) {
      TrayService().updateMenu();
    }
  }
  
  /// 获取当前歌曲的唯一 ID（使用 hashCode 统一处理 int 和 String）
  int? _getCurrentSongId(dynamic song, dynamic track) {
    if (song != null) {
      // song.id 可能是 int 或 String，使用 hashCode 统一处理
      return song.id?.hashCode ?? song.name.hashCode;
    } else if (track != null) {
      // track.id 可能是 int 或 String，使用 hashCode 统一处理
      return track.id?.hashCode ?? track.name.hashCode;
    }
    return null;
  }

  /// 更新 Windows 媒体信息（智能更新，避免频繁刷新）
  void _updateWindowsMedia(PlayerService player, dynamic song, dynamic track) {
    try {
      final currentSongId = _getCurrentSongId(song, track);
      final currentState = player.state;
      
      // 检查 SMTC 是否需要重新启用（在歌曲切换或状态改变时）
      final shouldEnableSmtc = _lastSongId == null && 
                               currentSongId != null && 
                               currentState != PlayerState.idle &&
                               currentState != PlayerState.error;
      
      if (shouldEnableSmtc) {
        print('▶️ [SystemMediaService] 重新启用 SMTC');
        _nativeSmtc!.enable();
      }
      
      // 1. 检查是否是新歌曲，只在歌曲切换时更新元数据
      final isSongChanged = currentSongId != _lastSongId && currentSongId != null;
      if (isSongChanged) {
        print('🎵 [SystemMediaService] 歌曲切换，更新元数据...');
        _updateMetadata(song, track);
        _lastSongId = currentSongId;
      }
      
      // 2. 检查播放状态是否改变，只在状态改变时更新
      final isStateChanged = currentState != _lastPlayerState;
      if (isStateChanged) {
        final status = _getPlaybackStatus(currentState);
        print('🎮 [SystemMediaService] 状态改变: ${currentState.name} -> ${status.value}');
        
        _nativeSmtc!.updatePlaybackStatus(status);
        _lastPlayerState = currentState;
        
        // 如果是停止或空闲状态，禁用 SMTC
        if (status == SmtcPlaybackStatus.stopped && currentState == PlayerState.idle) {
          print('⏹️ [SystemMediaService] 停止播放，禁用 SMTC');
          _nativeSmtc!.disable();
          _lastSongId = null; // 清除缓存，下次播放时重新更新元数据
        }
      }
      
      // 3. 只在播放中且有有效时长时更新 timeline（进度信息）
      // 注意：不要每次都更新，timeline 会自动推进
      if (currentState == PlayerState.playing && 
          player.duration.inMilliseconds > 0 &&
          (isSongChanged || isStateChanged)) {
        print('⏱️ [SystemMediaService] 更新播放进度');
        
        _nativeSmtc!.updateTimeline(
          startTimeMs: 0,
          endTimeMs: player.duration.inMilliseconds,
          positionMs: player.position.inMilliseconds,
          minSeekTimeMs: 0,
          maxSeekTimeMs: player.duration.inMilliseconds,
        );
      }
    } catch (e) {
      print('❌ [SystemMediaService] 更新 Windows 媒体信息失败: $e');
    }
  }
  
  /// 更新元数据（标题、艺术家、封面等）
  void _updateMetadata(dynamic song, dynamic track) {
    if (song == null && track == null) {
      print('⚠️ [SystemMediaService] 没有歌曲信息，跳过元数据更新');
      return;
    }
    
    final title = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知艺术家';
    final album = song?.alName ?? track?.album ?? '未知专辑';
    var thumbnail = PlayerService().currentCoverUrl ?? '';
    
    // 确保使用 HTTPS 协议（SMTC 要求）
    if (thumbnail.startsWith('http://')) {
      thumbnail = thumbnail.replaceFirst('http://', 'https://');
    }
    
    print('🖼️ [SystemMediaService] 更新元数据:');
    print('   📝 标题: $title');
    print('   👤 艺术家: $artist');
    print('   💿 专辑: $album');
    print('   🖼️ 封面: ${thumbnail.isNotEmpty ? "已设置" : "无"}');
    
    _nativeSmtc!.updateMetadata(
      title: title,
      artist: artist,
      album: album,
      thumbnail: thumbnail.isNotEmpty ? thumbnail : null,
    );
    
    print('✅ [SystemMediaService] 元数据已更新到 SMTC');
  }

  /// 将播放状态转换为 SMTC 播放状态
  SmtcPlaybackStatus _getPlaybackStatus(PlayerState state) {
    switch (state) {
      case PlayerState.playing:
        return SmtcPlaybackStatus.playing;
      case PlayerState.paused:
        return SmtcPlaybackStatus.paused;
      case PlayerState.loading:
        return SmtcPlaybackStatus.changing;
      default:
        return SmtcPlaybackStatus.stopped;
    }
  }

  /// 清理资源
  void dispose() {
    if (_isDisposed) {
      print('⚠️ [SystemMediaService] 已经清理过，跳过');
      return;
    }
    
    print('🎵 [SystemMediaService] 开始清理系统媒体控件...');
    
    // 立即设置标志，阻止继续更新（必须在最前面）
    _isDisposed = true;
    _initialized = false;
    
    try {
      // 移除播放器监听器（防止后续状态改变触发更新）
      print('🔌 [SystemMediaService] 移除播放器监听器...');
      PlayerService().removeListener(_onPlayerStateChanged);
      
      // 清除缓存状态
      _lastSongId = null;
      _lastPlayerState = null;
      
      // 释放 SMTC（不等待，让系统自动清理）
      if (_nativeSmtc != null) {
        print('🗑️ [SystemMediaService] 释放 SMTC 资源...');
        _nativeSmtc?.dispose();
        _nativeSmtc = null;
      }
      
      // 释放 Android AudioHandler
      if (_audioHandler != null) {
        print('🗑️ [SystemMediaService] 释放 AudioHandler 资源...');
        _audioHandler = null;
      }
      
      print('✅ [SystemMediaService] 系统媒体控件已清理');
    } catch (e) {
      print('⚠️ [SystemMediaService] 清理失败: $e');
    }
  }
}

