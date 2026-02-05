import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/player_service.dart';
import '../services/player_background_service.dart';
import '../models/lyric_line.dart';
import '../models/song_detail.dart';
import '../utils/lyric_parser.dart';
import 'mobile_lyric_page.dart';
import 'mobile_player_components/mobile_player_background.dart';
import 'mobile_player_components/mobile_player_app_bar.dart';
import 'mobile_player_components/mobile_player_song_info.dart';
import 'mobile_player_components/mobile_player_controls.dart';
import 'mobile_player_components/mobile_player_control_center.dart';
import 'mobile_player_components/mobile_player_karaoke_lyric.dart';
import 'mobile_player_components/mobile_player_fluid_cloud_layout.dart';
import 'mobile_player_components/mobile_player_classic_layout.dart';
import 'mobile_player_components/mobile_player_dialogs.dart';
import 'mobile_player_components/mobile_player_settings_sheet.dart';
import 'player_components/player_immersive_layout.dart';
import 'player_components/player_fluid_cloud_layout.dart';
import '../../services/lyric_style_service.dart';
import '../utils/theme_manager.dart';

/// 移动端播放器页面（重构版本）
/// 适用于 Android/iOS，现在使用组件化架构
class MobilePlayerPage extends StatefulWidget {
  const MobilePlayerPage({super.key});

  @override
  State<MobilePlayerPage> createState() => _MobilePlayerPageState();
}

class _MobilePlayerPageState extends State<MobilePlayerPage> with TickerProviderStateMixin {
  // 歌词相关
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  String? _lastTrackId;
  
  // 控制中心
  bool _showControlCenter = false;
  bool _showTranslation = true;
  AnimationController? _controlCenterAnimationController;
  Animation<double>? _controlCenterFadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupListeners();
    _initializeData();
    // 初始检查：如果当前已经是沉浸模式，强制横屏
    _checkAndForceOrientation();
  }

  /// 根据当前歌词样式检查并强制设置屏幕方向
  void _checkAndForceOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    
    if (LyricStyleService().currentStyle == LyricStyle.immersive) {
      print('📱 [MobilePlayerPage] 进入沉浸模式，强制横屏并隐藏状态栏');
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 进入全屏沉浸模式，隐藏状态栏和虚拟按键
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // 恢复系统默认（跟随重力感应或恢复到原本的设置，这里设为所有方向以解除锁定）
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 恢复状态栏和虚拟按键显示
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// 恢复到默认竖屏（用于关闭播放器时）
  void _resetOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    print('📱 [MobilePlayerPage] 离开播放页，恢复默认方向');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 确保退出时恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 是否应该显示译文按钮（与全屏歌词页一致逻辑）
  bool _shouldShowTranslationButton() {
    if (_lyrics.isEmpty) return false;
    final hasTranslation = _lyrics.any((l) => l.translation != null && l.translation!.isNotEmpty);
    if (!hasTranslation) return false;
    final sample = _lyrics.where((l) => l.text.trim().isNotEmpty).take(5).map((l) => l.text).join('');
    if (sample.isEmpty) return false;
    final chineseCount = sample.runes.where((r) =>
      (r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF) || (r >= 0x20000 && r <= 0x2A6DF)
    ).length;
    final ratio = chineseCount / sample.length;
    return ratio < 0.3; // 中文占比小于30%判定为外文
  }

  @override
  void dispose() {
    _resetOrientation();
    _disposeAnimations();
    _removeListeners();
    super.dispose();
  }

  /// 初始化动画控制器
  void _initializeAnimations() {
    _controlCenterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _controlCenterFadeAnimation = CurvedAnimation(
      parent: _controlCenterAnimationController!,
      curve: Curves.easeInOut,
    );
  }

  /// 设置监听器
  void _setupListeners() {
    PlayerService().addListener(_onPlayerStateChanged);
    PlayerService().positionNotifier.addListener(_onPositionChanged);
    LyricStyleService().addListener(_onLyricStyleChanged);
  }

  /// 移除监听器
  void _removeListeners() {
    PlayerService().removeListener(_onPlayerStateChanged);
    PlayerService().positionNotifier.removeListener(_onPositionChanged);
    LyricStyleService().removeListener(_onLyricStyleChanged);
  }

  void _onLyricStyleChanged() {
    if (mounted) {
      _checkAndForceOrientation();
      setState(() {});
    }
  }

  /// 释放动画控制器
  void _disposeAnimations() {
    _controlCenterAnimationController?.dispose();
  }

  /// 初始化数据
  void _initializeData() {
    // 延迟加载歌词，让路由动画先完成 (300ms 动画 + 50ms 缓冲)
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final currentTrack = PlayerService().currentTrack;
      _lastTrackId = currentTrack != null 
          ? '${currentTrack.source.name}_${currentTrack.id}' 
          : null;
      _loadLyrics();
    });
  }

  /// 播放器状态变化回调（与桌面端保持一致的逻辑）
  void _onPlayerStateChanged() {
    if (!mounted) return;
    
    final currentTrack = PlayerService().currentTrack;
    final currentTrackId = currentTrack != null 
        ? '${currentTrack.source.name}_${currentTrack.id}' 
        : null;
    
    if (currentTrackId != _lastTrackId) {
      // 歌曲已切换，重新加载歌词
      print('🎵 [MobilePlayerPage] 检测到歌曲切换，重新加载歌词');
      print('   上一首ID: $_lastTrackId');
      print('   当前ID: $currentTrackId');
      
      _lastTrackId = currentTrackId;
        _lyrics = [];
        _currentLyricIndex = -1;
          _loadLyrics();
      setState(() {}); // 触发重建以更新UI
    } else {
      // 这里的全局通知不再包含进度变化，主要是为了捕获除了切歌以外的状态变更（如暂停/恢复）
      if (mounted) setState(() {}); 
    }
  }

  /// 进度变化回调（高频，仅由 positionNotifier 触发）
  void _onPositionChanged() {
    if (!mounted) return;
    _updateCurrentLyric();
  }

  /// 加载歌词（异步执行，不阻塞 UI）
  Future<void> _loadLyrics() async {
    final currentTrack = PlayerService().currentTrack;
    if (currentTrack == null) return;

    print('🔍 [MobilePlayerPage] 开始加载歌词，当前 Track: ${currentTrack.name}');
    print('   Track ID: ${currentTrack.id} (类型: ${currentTrack.id.runtimeType})');

    // 等待 currentSong 更新（最多等待3秒）
    SongDetail? song;
    final startTime = DateTime.now();
    int attemptCount = 0;
    
    while (song == null && DateTime.now().difference(startTime).inSeconds < 3) {
      song = PlayerService().currentSong;
      attemptCount++;
      
      // 验证 currentSong 是否匹配 currentTrack
      if (song != null) {
        final songId = song.id.toString();
      final trackId = currentTrack.id.toString();
      
        if (attemptCount == 1) {
          print('🔍 [MobilePlayerPage] 找到 currentSong: ${song.name}');
          print('   Song ID: ${song.id} (类型: ${song.id.runtimeType})');
          print('   Track ID: ${currentTrack.id} (类型: ${currentTrack.id.runtimeType})');
          print('   ID 匹配: ${songId == trackId}');
        }
        
        // 如果 ID 不匹配，说明 currentSong 还没更新
        if (songId != trackId) {
          if (attemptCount <= 3) {
            print('⚠️ [MobilePlayerPage] ID 不匹配！Song ID: "$songId" vs Track ID: "$trackId"');
          }
          song = null;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    if (song == null) {
      print('❌ [MobilePlayerPage] 等待歌曲详情超时！');
      print('   尝试次数: $attemptCount');
      print('   Track: ${currentTrack.name} (ID: ${currentTrack.id})');
      final currentSong = PlayerService().currentSong;
      if (currentSong != null) {
        print('   CurrentSong 存在但 ID 不匹配: ${currentSong.name} (ID: ${currentSong.id})');
      } else {
        print('   CurrentSong 为 null');
      }
      return;
    }

    // 使用本地变量确保非空
    final songDetail = song;

    try {
      print('📝 [MobilePlayerPage] 开始解析歌词');
      print('   歌曲名: ${songDetail.name}');
      print('   歌曲ID: ${songDetail.id}');
      print('   原始歌词长度: ${songDetail.lyric.length} 字符');
      print('   翻译长度: ${songDetail.tlyric.length} 字符');
      
      // 关键诊断：检查歌词内容
      if (songDetail.lyric.isEmpty) {
        print('   ❌ 错误：MobilePlayerPage 读取到的 currentSong.lyric 为空！');
        print('   这说明 PlayerService.currentSong 中的歌词确实是空的');
      } else {
        print('   ✅ MobilePlayerPage 成功读取到歌词数据');
        print('   歌词预览: ${songDetail.lyric.substring(0, songDetail.lyric.length > 50 ? 50 : songDetail.lyric.length)}...');
      }
      
      // 使用 Future.microtask 确保异步执行
      await Future.microtask(() {
        // 根据音乐来源选择不同的解析器
        switch (songDetail.source.name) {
          case 'netease':
            _lyrics = LyricParser.parseNeteaseLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
              yrcLyric: songDetail.yrc.isNotEmpty ? songDetail.yrc : null,
              yrcTranslation: songDetail.ytlrc.isNotEmpty ? songDetail.ytlrc : null,
            );
            break;
          case 'qq':
            _lyrics = LyricParser.parseQQLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
            );
            break;
          case 'kugou':
            _lyrics = LyricParser.parseKugouLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
            );
            break;
          default:
            // 默认使用网易云/标准 LRC 格式解析（适用于酷我等）
            _lyrics = LyricParser.parseNeteaseLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
              yrcLyric: songDetail.yrc.isNotEmpty ? songDetail.yrc : null,
              yrcTranslation: songDetail.ytlrc.isNotEmpty ? songDetail.ytlrc : null,
            );
            break;
        }
      });

      if (_lyrics.isEmpty && songDetail.lyric.isNotEmpty) {
        print('⚠️ [MobilePlayerPage] 歌词解析结果为空，但原始歌词不为空！');
        print('   原始歌词前100字符: ${songDetail.lyric.substring(0, songDetail.lyric.length > 100 ? 100 : songDetail.lyric.length)}');
      }

      print('🎵 [MobilePlayerPage] 加载歌词: ${_lyrics.length} 行 (${songDetail.name})');
      
      // 加载歌词后，更新并滚动到当前位置
      if (_lyrics.isNotEmpty && mounted) {
        setState(() {
          _updateCurrentLyric();
        });
      }
    } catch (e) {
      print('❌ [MobilePlayerPage] 加载歌词失败: $e');
      print('   Stack trace: ${StackTrace.current}');
    }
  }

  /// 更新当前歌词
  void _updateCurrentLyric() {
    if (_lyrics.isEmpty) return;
    
    final newIndex = LyricParser.findCurrentLineIndex(
      _lyrics,
      PlayerService().position,
    );

    if (newIndex != _currentLyricIndex && newIndex >= 0 && mounted) {
      setState(() {
        _currentLyricIndex = newIndex;
      });
    }
  }

  /// 强制刷新歌词（用于调试）
  void _forceRefreshLyrics() {
    final currentTrack = PlayerService().currentTrack;
    if (currentTrack != null) {
      print('🔄 [MobilePlayerPage] 强制刷新歌词');
      setState(() {
        _lyrics = [];
        _currentLyricIndex = -1;
      });
      _loadLyrics();
    }
  }

  /// 切换控制中心显示状态
  void _toggleControlCenter() {
    setState(() {
      _showControlCenter = !_showControlCenter;
      if (_showControlCenter) {
        _controlCenterAnimationController?.forward();
      } else {
        _controlCenterAnimationController?.reverse();
      }
    });
  }

  /// 构建流体云全屏布局（动态背景模式）
  /// 使用新的 MobilePlayerFluidCloudLayout，不再需要二级歌词页面
  Widget _buildAppleMusicStyleLayout(BuildContext context, BoxConstraints constraints) {
    return MobilePlayerFluidCloudLayout(
      lyrics: _lyrics,
      currentLyricIndex: _currentLyricIndex,
      showTranslation: true,
      onBackPressed: () => Navigator.pop(context),
      onPlaylistPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    // 播放器页面始终使用深色背景，状态栏和导航栏透明，图标为浅色
    const playerOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    if (song == null && track == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: playerOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: playerOverlayStyle,
          ),
          body: const Center(
            child: Text(
              '暂无播放内容',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }

    // 构建主要内容
    final backgroundService = PlayerBackgroundService();
    final lyricStyleService = LyricStyleService();
    // 流体云布局条件：全屏播放器样式设置为流体云（优先级最高）
    final useFluidCloudLayout = lyricStyleService.currentStyle == LyricStyle.fluidCloud;
    
    // 动态处理状态栏：如果是沉浸模式，或者在流体云样式下的横屏，则隐藏状态栏
    final isImmersive = lyricStyleService.currentStyle == LyricStyle.immersive;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    if (isImmersive || (useFluidCloudLayout && isLandscape)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    final scaffoldWidget = AnnotatedRegion<SystemUiOverlayStyle>(
      value: playerOverlayStyle,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
            children: [
              // 沉浸模式布局：复用桌面端组件
              if (lyricStyleService.currentStyle == LyricStyle.immersive)
                PlayerImmersiveLayout(
                  lyrics: _lyrics,
                  currentLyricIndex: _currentLyricIndex,
                  showTranslation: _showTranslation,
                  isMaximized: true,
                  uiScale: 0.5, // 适配移动端，缩小 50%
                  onBackPressed: () => Navigator.pop(context),
                  onMorePressed: () => MobilePlayerSettingsSheet.show(context),
                  onPlaylistPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
                  onVolumeControlPressed: () {
                    // 移动端通过系统按键控制音量，此处保持为空
                  },
                )
              // 流体云布局模式：完全接管背景和 Safe Area
              else if (useFluidCloudLayout)
                ThemeManager().isTablet
                    ? PlayerFluidCloudLayout(
                        lyrics: _lyrics,
                        currentLyricIndex: _currentLyricIndex,
                        showTranslation: _showTranslation,
                        isMaximized: true,
                        onBackPressed: () => Navigator.pop(context),
                        onPlaylistPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
                        onVolumeControlPressed: () {
                          // 移动端通过系统按键控制音量，内部 Slider 会直接调用 PlayerService().setVolume
                        },
                        onSleepTimerPressed: () => MobilePlayerDialogs.showSleepTimer(context),
                        onTranslationToggle: () => setState(() => _showTranslation = !_showTranslation),
                        leftPanelScale: 0.75, // 缩小左侧区域
                      )
                    : _buildAppleMusicStyleLayout(context, const BoxConstraints())
              else ...[
                // 标准布局模式：原有背景 + Safe Area
                const MobilePlayerBackground(),
                SafeArea(
                  child: MobilePlayerClassicLayout(
                    lyrics: _lyrics,
                    currentLyricIndex: _currentLyricIndex,
                    onBackPressed: () => Navigator.pop(context),
                    onPlaylistPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
                  ),
                ),
              ],

          // 控制中心面板
          MobilePlayerControlCenter(
            isVisible: _showControlCenter,
            fadeAnimation: _controlCenterFadeAnimation,
            onClose: _toggleControlCenter,
          ),
        ],
      ),
      ),
    );
    
    // Windows 平台：添加圆角边框
    if (Platform.isWindows) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: scaffoldWidget,
      );
    }
    
    return scaffoldWidget;
  }
}
