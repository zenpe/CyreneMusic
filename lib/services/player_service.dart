import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' show ImageProvider; // for cover provider
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'color_extraction_service.dart';
import '../models/song_detail.dart';
import '../models/track.dart';
import '../models/lyric_line.dart';
import '../utils/lyric_parser.dart';
import 'music_service.dart';
import 'audio_source_service.dart';
import 'cache_service.dart';
import 'proxy_service.dart';
import 'play_history_service.dart';
import 'playback_mode_service.dart';
import 'playlist_queue_service.dart';
import 'audio_quality_service.dart';
import 'listening_stats_service.dart';
import 'desktop_lyric_service.dart';
import 'android_floating_lyric_service.dart';
import 'player_background_service.dart';
import 'local_library_service.dart';
import 'playback_state_service.dart';
import 'developer_mode_service.dart';
import 'url_service.dart';
import 'notification_service.dart';
import 'persistent_storage_service.dart';
import 'equalizer_service.dart';
import 'app_settings_service.dart';
import 'dart:async' as async_lib;
import 'dart:async' show TimeoutException;
import '../utils/toast_utils.dart';
import '../utils/metadata_reader.dart';
import 'package:wakelock_plus/wakelock_plus.dart';


/// 播放状态枚举
enum PlayerState {
  idle,     // 空闲
  loading,  // 加载中
  playing,  // 播放中
  paused,   // 暂停
  error,    // 错误
}

/// 音乐播放器服务
class PlayerService extends ChangeNotifier {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;
  PlayerService._internal();

  ap.AudioPlayer? _audioPlayer; // 延迟初始化，避免启动时杂音
  mk.Player? _mediaKitPlayer;
  bool _useMediaKit = false;
  
  // 判断当前平台是否应该使用 MediaKit
  bool get _shouldUseMediaKit => Platform.isWindows || Platform.isMacOS || Platform.isLinux || Platform.isAndroid;

  async_lib.StreamSubscription<bool>? _mediaKitPlayingSub;
  async_lib.StreamSubscription<Duration>? _mediaKitPositionSub;
  async_lib.StreamSubscription<Duration?>? _mediaKitDurationSub;
  async_lib.StreamSubscription<bool>? _mediaKitCompletedSub;
  
  PlayerState _state = PlayerState.idle;
  SongDetail? _currentSong;
  Track? _currentTrack;
  int _playGeneration = 0; // 切歌代数，用于丢弃旧异步操作的回写
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _errorMessage;
  String? _currentTempFilePath;  // 记录当前临时文件路径
  final Map<String, Color> _themeColorCache = {}; // 主题色缓存
  final ValueNotifier<Color?> themeColorNotifier = ValueNotifier<Color?>(null); // 主题色通知器
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(Duration.zero); // 进度通知器（高频更新，单独解耦）
  DateTime _lastNativeSyncTime = DateTime.fromMillisecondsSinceEpoch(0); // 上次同步到原生层的时间
  double _volume = 0.7; // 当前音量 (0.0 - 1.0)，默认 70% 避免破音
  ImageProvider? _currentCoverImageProvider; // 当前歌曲的预取封面图像提供器（避免二次请求）
  String? _currentCoverUrl; // 当前封面图对应的原始 URL（用于去重）
  
  // 听歌统计相关
  async_lib.Timer? _statsTimer; // 统计定时器
  DateTime? _playStartTime; // 播放开始时间
  int _sessionListeningTime = 0; // 当前会话累积的听歌时长

  // 播放状态保存定时器
  async_lib.Timer? _stateSaveTimer;

  // 桌面歌词相关
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;

  // 音源配置状态
  bool _isAudioSourceNotConfigured = false;
  
  // 音源未配置回调（用于 UI 显示弹窗）
  void Function()? onAudioSourceNotConfigured;
  
  // 均衡器相关 — 委托给 EqualizerService
  static List<int> get kEqualizerFrequencies => EqualizerService.kEqualizerFrequencies;

  List<double> get equalizerGains => EqualizerService().equalizerGains;
  bool get equalizerEnabled => EqualizerService().equalizerEnabled;

  PlayerState get state => _state;
  SongDetail? get currentSong => _currentSong;
  Track? get currentTrack => _currentTrack;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _state == PlayerState.playing;
  bool get isPaused => _state == PlayerState.paused;
  bool get isLoading => _state == PlayerState.loading;
  double get volume => _volume; // 获取当前音量
  ImageProvider? get currentCoverImageProvider => _currentCoverImageProvider;
  String? get currentCoverUrl => _currentCoverUrl;
  
  /// 是否因音源未配置导致播放失败
  bool get isAudioSourceNotConfigured => _isAudioSourceNotConfigured;

  /// 设置当前歌曲的预取封面图像提供器
  void setCurrentCoverImageProvider(
    ImageProvider? provider, {
    bool shouldNotify = false,
    String? imageUrl,
  }) {
    _currentCoverImageProvider = provider;

    if (provider is CachedNetworkImageProvider) {
      _currentCoverUrl = imageUrl ?? provider.url;
    } else {
      _currentCoverUrl = imageUrl;
    }

    if (provider == null) {
      _currentCoverUrl = null;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  /// 初始化播放器监听
  Future<void> initialize() async {
    // 🔧 关键修复：不在启动时创建 AudioPlayer，避免音频系统初始化导致的杂音
    // AudioPlayer 将在第一次播放时才创建和配置（见 _ensureAudioPlayerInitialized 方法）
    print('🎵 [PlayerService] 播放器服务已准备就绪（AudioPlayer 将在首次播放时初始化）');

    // 本地代理服务器改为按需启动，避免影响启动耗时

    // 加载保存的音量设置（但不应用到播放器，因为播放器还未创建）
    final savedVolume = PersistentStorageService().getDouble('player_volume');
    if (savedVolume != null) {
      _volume = savedVolume.clamp(0.0, 1.0);
      print('🔊 [PlayerService] 已加载保存的音量: ${(_volume * 100).toInt()}%');
    } else {
      print('🔊 [PlayerService] 使用默认音量: ${(_volume * 100).toInt()}%');
    }

    // 加载均衡器设置（委托给 EqualizerService）
    EqualizerService().loadSettings();

    // 设置桌面歌词播放控制回调（Windows）
    if (Platform.isWindows) {
      DesktopLyricService().setPlaybackControlCallback((action) {
        print('🎮 [PlayerService] 桌面歌词控制: $action');
        switch (action) {
          case 'play_pause':
            if (isPlaying) {
              pause();
            } else {
              resume();
            }
            break;
          case 'previous':
            playPrevious();
            break;
          case 'next':
            playNext();
            break;
        }
      });
      print('✅ [PlayerService] 桌面歌词播放控制回调已设置');
    }

    // 监听播放集与播放模式变化，触发预缓存
    PlaybackModeService().addListener(_precacheNextCover);
    PlaylistQueueService().addListener(_precacheNextCover);

    print('✅ [PlayerService] 预缓存监听器已设置');

    print('🎵 [PlayerService] 播放器初始化完成');
  }

  /// 确保播放器已初始化（首次播放时调用）
  Future<void> _ensurePlayerInitialized() async {
    if (_shouldUseMediaKit) {
      await _ensureMediaKitPlayer();
    } else {
      await _ensureAudioPlayerInitialized();
    }
  }

  /// 确保 AudioPlayer 已初始化（仅用于 iOS/Web 等非 MediaKit 平台）
  Future<void> _ensureAudioPlayerInitialized() async {
    if (_audioPlayer != null) return;

    print('🎵 [PlayerService] 首次播放，正在初始化 AudioPlayer...');
    _audioPlayer = ap.AudioPlayer();

    // 配置音频播放器（Android）
    if (Platform.isAndroid) {
      try {
        // 设置音频上下文
        await _audioPlayer!.setAudioContext(
          ap.AudioContext(
            android: const ap.AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: ap.AndroidContentType.music,
              usageType: ap.AndroidUsageType.media,
              audioFocus: ap.AndroidAudioFocus.gain,
            ),
          ),
        );
        print('✅ [PlayerService] Android 音频上下文已配置');
      } catch (e) {
        print('⚠️ [PlayerService] 配置音频上下文失败: $e');
      }
    }

    // 应用保存的音量设置
    await _audioPlayer!.setVolume(_volume);
    print('🔊 [PlayerService] 已应用音量设置: ${(_volume * 100).toInt()}%');

    // 监听播放状态
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      switch (state) {
        case ap.PlayerState.playing:
          _state = PlayerState.playing;
          _startListeningTimeTracking(); // 开始听歌时长追踪
          _startStateSaveTimer(); // 开始定期保存播放状态
          // 🔥 通知原生层播放状态（后台歌词更新关键）
          if (Platform.isAndroid) {
            AndroidFloatingLyricService().setPlayingState(true);
          }
          if (Platform.isWindows) {
            DesktopLyricService().setPlayingState(true);
          }
          break;
        case ap.PlayerState.paused:
          _state = PlayerState.paused;
          _pauseListeningTimeTracking(); // 暂停听歌时长追踪
          _saveCurrentPlaybackState(); // 暂停时保存状态
          _stopStateSaveTimer(); // 停止定期保存
          // 🔥 通知原生层播放状态（后台歌词更新关键）
          if (Platform.isAndroid) {
            AndroidFloatingLyricService().setPlayingState(false);
          }
          if (Platform.isWindows) {
            DesktopLyricService().setPlayingState(false);
          }
          break;
        case ap.PlayerState.stopped:
          _state = PlayerState.idle;
          _pauseListeningTimeTracking(); // 暂停听歌时长追踪
          _stopStateSaveTimer(); // 停止定期保存
          // 🔥 通知原生层播放状态（后台歌词更新关键）
          if (Platform.isAndroid) {
            AndroidFloatingLyricService().setPlayingState(false);
          }
          if (Platform.isWindows) {
            DesktopLyricService().setPlayingState(false);
          }
          break;
        case ap.PlayerState.completed:
          _state = PlayerState.idle;
          _position = Duration.zero;
          _pauseListeningTimeTracking(); // 暂停听歌时长追踪
          _stopStateSaveTimer(); // 停止定期保存
          // 🔥 通知原生层播放状态（后台歌词更新关键）
          if (Platform.isAndroid) {
            AndroidFloatingLyricService().setPlayingState(false);
          }
          if (Platform.isWindows) {
            DesktopLyricService().setPlayingState(false);
          }
          // 歌曲播放完毕，自动播放下一首
          _playNextFromHistory();
          break;
        default:
          break;
      }
      notifyListeners();
    });

    // 监听播放进度
    _audioPlayer!.onPositionChanged.listen((position) {
      _position = position;
      positionNotifier.value = position; // 更新独立的进度通知器
      _updateFloatingLyric(); // 更新桌面/悬浮歌词
      // 🔥 性能优化：使用节流同步到 Android 原生层（不再每帧同步）
      _syncPositionToNative(position);
      // 🔧 性能优化：不再在进度更新时调用 notifyListeners()，避免全局范围的 UI 重建
      // notifyListeners();
    });

    // 监听总时长
    _audioPlayer!.onDurationChanged.listen((duration) {
      _duration = duration;
      notifyListeners();
    });

    print('✅ [PlayerService] AudioPlayer 初始化完成');
  }

  /// 播放歌曲（通过Track对象）
  /// [fromPlaylist] 是否来自歌单，如果是则检查 Apple Music 换源限制
  Future<void> playTrack(
    Track track, {
    AudioQuality? quality,
    ImageProvider? coverProvider,
    bool fromPlaylist = false,
  }) async {
    try {
      // 🔧 关键修复：首次播放时才初始化播放器，避免启动时的杂音
      await _ensurePlayerInitialized();
      
      // 设置使用 MediaKit 标志
      _useMediaKit = _shouldUseMediaKit;

      // ✅ 提前检查音源配置（仅对在线音乐）
      // 本地音乐不需要音源，直接跳过此检查
      if (track.source != MusicSource.local) {
        if (!AudioSourceService().isConfigured) {
          print('⚠️ [PlayerService] 音源未配置，无法播放在线音乐');
          _state = PlayerState.error;
          _errorMessage = '音源未配置，请在设置中配置音源';
          _isAudioSourceNotConfigured = true;
          // ⚠️ 注意：不设置 _currentTrack，避免 UI 显示"正在播放"
          notifyListeners();
          
          // 调用回调通知 UI 显示提示
          if (onAudioSourceNotConfigured != null) {
            print('🔔 [PlayerService] 调用音源未配置回调');
            onAudioSourceNotConfigured!();
          }
          return;
        }
      }

      // 仅在歌单场景下检测 Apple Music 歌曲换源限制
      // 搜索结果页可以直接播放（使用后端 Widevine 解密）
      if (fromPlaylist && track.source == MusicSource.apple) {
        print('🍎 [PlayerService] 检测到歌单中的 Apple Music 歌曲，需要换源才能播放');
        _state = PlayerState.error;
        _errorMessage = '由于Apple接口限制，通过该接口导入的音乐需要换源才能播放！';
        _currentTrack = track;
        notifyListeners();
        
        // 通知用户（通过回调或事件）
        _notifyAppleMusicRestriction(track);
        
        // 移动端弹出 Toast 提示
        if (Platform.isAndroid || Platform.isIOS) {
          ToastUtils.error('Apple 播放限制: $_errorMessage');
        }
        return;
      }

      // 使用用户设置的音质，如果没有传入特定音质
      final selectedQuality = quality ?? AudioQualityService().currentQuality;
      print('🎵 [PlayerService] 播放音质: ${selectedQuality.toString()}');
      
      if (coverProvider != null) {
        setCurrentCoverImageProvider(
          coverProvider,
          shouldNotify: false,
          imageUrl: track.picUrl,
        );
      }

      // 清理上一首歌的临时文件
      await _cleanupCurrentTempFile();
      
      _state = PlayerState.loading;
      _currentTrack = track;
      _currentSong = null;
      _errorMessage = null;
      _isAudioSourceNotConfigured = false;  // 重置标志
      final gen = ++_playGeneration; // 记录本次播放代数
      final requestedTrackKey = '${track.source.name}_${track.id}';
      bool isStalePlay() {
        final currentTrack = _currentTrack;
        if (gen != _playGeneration || currentTrack == null) return true;
        final currentTrackKey = '${currentTrack.source.name}_${currentTrack.id}';
        return currentTrackKey != requestedTrackKey;
      }
      
      // ✅ 关键逻辑：如果是手动点击（未提供预取的 coverProvider），则强制刷新一次封面
      final shouldForceUpdate = coverProvider == null;
      await _updateCoverImage(track.picUrl, notify: false, force: shouldForceUpdate);
      if (isStalePlay()) return;
      
      notifyListeners();

      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero;
      
      // 触发下一首封面预缓存
      _precacheNextCover();

      // 🔥 启用屏幕常亮/CPU唤醒（防止后台播放卡顿）
      if (Platform.isAndroid || Platform.isIOS) {
        WakelockPlus.enable();
      }
      
      // 记录到播放历史 (✅ 优化：非阻塞调用)
      PlayHistoryService().addToHistory(track);
      
      // 记录播放次数 (✅ 优化：非阻塞调用)
      ListeningStatsService().recordPlayCount(track);

      // 1. 检查缓存
      final qualityStr = selectedQuality.toString().split('.').last;
      final isCached = CacheService().isCached(track);

      if (isCached) {
        print('💾 [PlayerService] 使用缓存播放');
        
        // 获取缓存的元数据
        final metadata = CacheService().getCachedMetadata(track);
        final cachedFilePath = await CacheService().getCachedFilePath(track);
        if (isStalePlay()) return;

        if (cachedFilePath != null && metadata != null) {
          // 记录临时文件路径（用于后续清理）
          _currentTempFilePath = cachedFilePath;
          
          _currentSong = SongDetail(
            id: track.id,
            name: track.name,
            url: cachedFilePath,
            pic: metadata.picUrl,
            arName: metadata.artists,
            alName: metadata.album,
            level: metadata.quality,
            size: metadata.fileSize.toString(),
            lyric: metadata.lyric,      // 从缓存恢复歌词
            tlyric: metadata.tlyric,    // 从缓存恢复翻译
            source: track.source,
          );
          
          // 如果缓存的封面图与 Track 的不同才更新 (通常相同)
          if (metadata.picUrl != track.picUrl) {
            await _updateCoverImage(metadata.picUrl, notify: false);
          }

          // 🔧 立即通知监听器，确保 PlayerPage 能获取到包含歌词的 currentSong
          notifyListeners();
          print('✅ [PlayerService] 已更新 currentSong（从缓存，包含歌词）');
          
          // 加载桌面歌词
          _loadLyricsForFloatingDisplay();

          // 播放缓存文件
          if (_shouldUseMediaKit) {
             print('✅ [PlayerService/MediaKit] 从缓存播放: $cachedFilePath');
             await _mediaKitPlayer!.open(mk.Media(cachedFilePath));
             await _mediaKitPlayer!.play();
          } else {
             await _audioPlayer!.play(ap.DeviceFileSource(cachedFilePath));
             print('✅ [PlayerService/AudioPlayer] 从缓存播放: $cachedFilePath');
          }
          print('📝 [PlayerService] 歌词已从缓存恢复 (长度: ${_currentSong!.lyric.length})');
          
          // 🔍 检查：如果缓存中歌词为空，尝试后台更新
          if (_currentSong!.lyric.isEmpty) {
            print('⚠️ [PlayerService] 缓存歌词为空，后台尝试更新元数据...');
            MusicService().fetchSongDetail(
              songId: track.id, 
              source: track.source,
              quality: selectedQuality,
              title: track.name,
              artist: track.artists,
            ).then((detail) {
               if (isStalePlay()) return; // 已切歌，丢弃

               final currentTrack = _currentTrack;
               final currentSong = _currentSong;
               if (currentTrack == null || currentSong == null) return;

               final currentTrackKey = '${currentTrack.source.name}_${currentTrack.id}';
               final currentSongKey = '${currentSong.source.name}_${currentSong.id}';
               if (currentTrackKey != requestedTrackKey || currentSongKey != requestedTrackKey) {
                 return;
               }

               if (detail != null && detail.lyric.isNotEmpty) {
                  print('✅ [PlayerService] 成功获取新歌词 (${detail.lyric.length}字符)');

                  // 更新当前歌曲对象（保留 URL 为缓存路径）
                  final updatedSong = SongDetail(
                    id: currentSong.id,
                    name: detail.name.isNotEmpty ? detail.name : currentSong.name,
                    url: currentSong.url, // 保持缓存路径
                    pic: detail.pic.isNotEmpty ? detail.pic : currentSong.pic,
                    arName: detail.arName.isNotEmpty ? detail.arName : currentSong.arName,
                    alName: detail.alName.isNotEmpty ? detail.alName : currentSong.alName,
                    level: currentSong.level,
                    size: currentSong.size,
                    lyric: detail.lyric,
                    tlyric: detail.tlyric,
                    source: currentSong.source,
                  );

                  _currentSong = updatedSong;

                  // 更新缓存
                  CacheService().cacheSong(track, updatedSong, qualityStr);

                  // 刷新 UI 和歌词
                  notifyListeners();
                  _loadLyricsForFloatingDisplay();
               } else {
                 print('❌ [PlayerService] 后台更新歌词失败或仍为空');
               }
            }).catchError((e) {
              print('❌ [PlayerService] 后台更新元数据失败: $e');
            });
          }
          
          // 提取主题色（即使是缓存播放也需要更新主题色）
          _extractThemeColorInBackground(metadata.picUrl);
          return;
        } else {
          print('⚠️ [PlayerService] 缓存文件无效，从网络获取');
        }
      }

      // 如果是本地文件，直接走本地播放
      if (track.source == MusicSource.local) {
        final filePath = track.id is String ? track.id as String : '';
        if (filePath.isEmpty || !(await File(filePath).exists())) {
          if (isStalePlay()) return;
          _state = PlayerState.error;
          _errorMessage = '本地文件不存在';
          notifyListeners();

          // 移动端弹出 Toast 提示
          if (Platform.isAndroid || Platform.isIOS) {
            ToastUtils.error('本地播放失败: $_errorMessage');
          }
          return;
        }

        // 从本地服务取歌词
        var lyricText = LocalLibraryService().getLyricByTrackId(filePath);

        // 如果 LocalLibrary 没有该文件歌词（可能是外部 Pick 的），尝试实时解析
        if (lyricText.isEmpty) {
          print('🔍 [PlayerService] 本地库未找到歌词，尝试从文件实时提取...');
          final embeddedLyric = await MetadataReader.extractLyrics(filePath);
          if (embeddedLyric != null && embeddedLyric.isNotEmpty) {
            lyricText = embeddedLyric;
            print('✅ [PlayerService] 实时提取内嵌歌词成功');
          }
        }

        _currentSong = SongDetail(
          id: filePath,
          name: track.name,
          pic: track.picUrl,
          arName: track.artists,
          alName: track.album,
          level: 'local',
          size: '',
          url: filePath,
          lyric: lyricText,
          tlyric: '',
          source: MusicSource.local,
        );

        // 本地歌曲已在 playTrack 开始时更新过轨道封面，此处不再重复更新
        // 如果本地文件有嵌入封面（目前逻辑尚未支持动态提取到 _currentSong.pic），则后续再按需扩展

        notifyListeners();
        _loadLyricsForFloatingDisplay();

        if (_shouldUseMediaKit) {
           print('✅ [PlayerService/MediaKit] 播放本地文件: $filePath');
           await _mediaKitPlayer!.open(mk.Media(filePath));
           await _mediaKitPlayer!.play();
        } else {
           await _audioPlayer!.play(ap.DeviceFileSource(filePath));
           print('✅ [PlayerService/AudioPlayer] 播放本地文件: $filePath');
        }
        _extractThemeColorInBackground(track.picUrl);
        return;
      }

      // 2. 从网络获取歌曲详情
      print('🌐 [PlayerService] 从网络获取歌曲');
      var songDetail = await MusicService().fetchSongDetail(
        songId: track.id,
        quality: selectedQuality,
        source: track.source,
        title: track.name,
        artist: track.artists,
      );

      // 异步返回后检查是否已切歌
      if (isStalePlay()) {
        print('⏭️ [PlayerService] 已切歌(gen=$gen→$_playGeneration)，丢弃 fetchSongDetail 结果');
        return;
      }

      if (songDetail == null || songDetail.url.isEmpty) {
        _state = PlayerState.error;
        _errorMessage = '无法获取播放链接';
        print('❌ [PlayerService] 播放失败: $_errorMessage');
        notifyListeners();

        // 移动端弹出 Toast 提示
        if (Platform.isAndroid || Platform.isIOS) {
          ToastUtils.error('获取 URL 失败: $_errorMessage');
        }
        return;
      }

      // 🔧 修复：如果详情中的信息为空，使用 Track 中的信息填充
      // 这种情况常见于酷我音乐等平台，详情接口可能缺少部分元数据
      if (songDetail.name.isEmpty || songDetail.arName.isEmpty || songDetail.pic.isEmpty) {
         print('⚠️ [PlayerService] 歌曲详情缺失元数据，使用 Track 信息填充');
         songDetail = SongDetail(
            id: songDetail.id,
            name: songDetail.name.isNotEmpty ? songDetail.name : track.name,
            pic: songDetail.pic.isNotEmpty ? songDetail.pic : track.picUrl,
            arName: songDetail.arName.isNotEmpty ? songDetail.arName : track.artists,
            alName: songDetail.alName.isNotEmpty ? songDetail.alName : track.album,
            level: songDetail.level,
            size: songDetail.size,
            url: songDetail.url,
            lyric: songDetail.lyric,
            tlyric: songDetail.tlyric,
            source: songDetail.source,
         );
      }

      // 检查歌词是否获取成功
      print('📝 [PlayerService] 从网络获取的歌曲详情:');
      print('   歌曲名: ${songDetail.name}');
      print('   歌词长度: ${songDetail.lyric.length} 字符');
      print('   翻译长度: ${songDetail.tlyric.length} 字符');
      if (songDetail.lyric.isEmpty) {
        print('   ⚠️ 警告：从网络获取的歌曲详情中歌词为空！');
      } else {
        print('   ✅ 歌词获取成功');
      }

      if (track.source == MusicSource.apple &&
          !songDetail.url.contains('/apple/stream')) {
        final baseUrl = UrlService().baseUrl;
        final salableAdamId = Uri.encodeComponent(track.id.toString());
        final decryptedStreamUrl =
            '$baseUrl/apple/stream?salableAdamId=$salableAdamId';

        songDetail = SongDetail(
          id: songDetail.id,
          name: songDetail.name,
          pic: songDetail.pic,
          arName: songDetail.arName,
          alName: songDetail.alName,
          level: songDetail.level,
          size: songDetail.size,
          url: decryptedStreamUrl,
          lyric: songDetail.lyric,
          tlyric: songDetail.tlyric,
          source: songDetail.source,
        );
      }

      _currentSong = songDetail;
      
      // 如果获取到的详情封面与预期的不同才更新
      if (songDetail.pic != track.picUrl) {
        await _updateCoverImage(songDetail.pic, notify: false);
        if (isStalePlay()) return;
      }

      // 🔧 修复：立即通知监听器，让 PlayerPage 能获取到包含歌词的 currentSong
      notifyListeners();
      print('✅ [PlayerService] 已更新 currentSong 并通知监听器（包含歌词）');
      
      // 加载桌面/悬浮歌词
      _loadLyricsForFloatingDisplay();

      // Apple Music 播放逻辑
      // 如果 URL 是后端解密流端点（/apple/stream），流式播放并从响应头获取时长
      // 如果 URL 是原始 HLS m3u8 流，所有支持 MediaKit 的平台（包括 Android）使用 media_kit 播放
      if (track.source == MusicSource.apple) {
        final isDecryptedStream = songDetail.url.contains('/apple/stream');
        
        if (isDecryptedStream) {
          // 使用后端解密流端点，流式播放
          print('🔐 [PlayerService] Apple Music 使用解密流端点（流式播放）');
          DeveloperModeService().addLog('🔐 [PlayerService] Apple Music 使用解密流端点');
          try {
            // 先通过 HEAD 请求获取音频时长
            final durationMs = await _getAppleStreamDuration(songDetail.url);
            if (durationMs != null && durationMs > 0) {
              _duration = Duration(milliseconds: durationMs);
              print('📏 [PlayerService] 从后端获取时长: ${_duration.inSeconds}s');
              DeveloperModeService().addLog('📏 [PlayerService] 时长: ${_duration.inSeconds}s');
              notifyListeners();
            }
            
            // 流式播放
            if (_shouldUseMediaKit) {
               await _mediaKitPlayer!.open(mk.Media(songDetail.url));
               await _mediaKitPlayer!.play();
            } else {
               await _audioPlayer!.play(ap.UrlSource(songDetail.url));
            }
            print('✅ [PlayerService] Apple Music 解密流播放成功');
            DeveloperModeService().addLog('✅ [PlayerService] Apple Music 解密流播放成功');
            return;
          } catch (e) {
            print('❌ [PlayerService] Apple Music 解密流播放失败: $e');
            DeveloperModeService().addLog('❌ [PlayerService] Apple Music 解密流播放失败: $e');
            if (isStalePlay()) return;
            _state = PlayerState.error;
            _errorMessage = 'Apple Music 播放失败: $e';
            notifyListeners();

            // 移动端弹出 Toast 提示
            if (Platform.isAndroid || Platform.isIOS) {
              ToastUtils.error('播放失败: $_errorMessage');
            }
            return;
          }
        } else if (_shouldUseMediaKit) {
          // 原始 HLS 流，MediaKit 支持 HLS
          await _playAppleWithMediaKit(songDetail);
          return;
        }
        // 移动端（非 MediaKit）继续使用下面的代理逻辑
      }

      // 3. 播放音乐
      if (track.source == MusicSource.qq ||
          track.source == MusicSource.kugou ||
          track.source == MusicSource.apple) {
        // 需要代理播放的平台
        DeveloperModeService().addLog('🎶 [PlayerService] 准备播放 ${track.getSourceName()} 音乐');
        final platform = track.source == MusicSource.qq
            ? 'qq'
            : track.source == MusicSource.kugou
                ? 'kugou'
                : 'apple';
        
        // iOS 使用服务器代理，Android/桌面端使用本地代理（节省服务器带宽）
        // Android 已配置 network_security_config.xml 允许 localhost HTTP 流量
        // Apple Music 需要本地代理来处理 m3u8 及鉴权请求头
        final useServerProxy = Platform.isIOS && platform != 'apple';
        
        if (useServerProxy) {
          // iOS：使用服务器代理流式播放，失败则下载后播放
          DeveloperModeService().addLog('📱 [PlayerService] iOS 使用服务器代理');
          final serverProxyUrl = _getServerProxyUrl(songDetail.url, platform);
          DeveloperModeService().addLog('🔗 [PlayerService] 服务器代理URL: ${serverProxyUrl.length > 80 ? '${serverProxyUrl.substring(0, 80)}...' : serverProxyUrl}');
          
          try {
            // 先尝试流式播放
            if (_shouldUseMediaKit) {
               await _seekToStart(); // MediaKit 有时不重置
               await _mediaKitPlayer!.open(mk.Media(serverProxyUrl));
               await _mediaKitPlayer!.play();
            } else {
               await _audioPlayer!.play(ap.UrlSource(serverProxyUrl));
            }
            print('✅ [PlayerService] 通过服务器代理流式播放成功');
            DeveloperModeService().addLog('✅ [PlayerService] 通过服务器代理流式播放成功');
          } catch (playError) {
            // 流式播放失败，回退到下载后播放
            print('⚠️ [PlayerService] 流式播放失败，尝试下载后播放: $playError');
            DeveloperModeService().addLog('⚠️ [PlayerService] 流式播放失败: $playError');
            DeveloperModeService().addLog('🔄 [PlayerService] 回退到下载后播放');
            final tempFilePath = await _downloadViaProxyAndPlay(serverProxyUrl, songDetail.name, songDetail.level);
            if (tempFilePath != null) {
              _currentTempFilePath = tempFilePath;
            }
          }
        } else {
          // Android/桌面端：使用本地代理
          final platformName = Platform.isAndroid ? 'Android' : '桌面端';
          DeveloperModeService().addLog('📱 [PlayerService] $platformName 使用本地代理');
          final proxyReady = await _ensureLocalProxyRunning(platform);
          DeveloperModeService().addLog('🔍 [PlayerService] 本地代理状态: ${proxyReady ? "运行中 (端口: ${ProxyService().port})" : "未运行"}');
          
          if (proxyReady) {
            final proxyUrl = ProxyService().getProxyUrl(songDetail.url, platform);
            DeveloperModeService().addLog('🔗 [PlayerService] 本地代理URL: ${proxyUrl.length > 80 ? '${proxyUrl.substring(0, 80)}...' : proxyUrl}');
            
            try {
              if (_shouldUseMediaKit) {
                 await _seekToStart();
                 await _mediaKitPlayer!.open(mk.Media(proxyUrl));
                 await _mediaKitPlayer!.play();
              } else {
                 await _audioPlayer!.play(ap.UrlSource(proxyUrl));
              }
              print('✅ [PlayerService] 通过本地代理开始流式播放');
              DeveloperModeService().addLog('✅ [PlayerService] 通过本地代理开始流式播放');
            } catch (playError) {
              print('❌ [PlayerService] 本地代理播放失败: $playError');
              DeveloperModeService().addLog('❌ [PlayerService] 本地代理播放失败: $playError');

              if (platform == 'apple') {
                // Apple Music 不支持“下载后播放”（m3u8 不是音频文件）
                try {
                  DeveloperModeService().addLog('🔄 [PlayerService] Apple 尝试直接播放原始 URL');
                  await _audioPlayer!.play(ap.UrlSource(songDetail.url));
                } catch (e) {
                  if (isStalePlay()) return;
                  _state = PlayerState.error;
                  _errorMessage = 'Apple Music 播放失败（本地代理/直连均失败）';
                  notifyListeners();
                  
                  // 移动端弹出 Toast 提示
                  if (Platform.isAndroid || Platform.isIOS) {
                    ToastUtils.error('播放链接异常: $_errorMessage');
                  }
                  return;
                }
              } else {
                DeveloperModeService().addLog('🔄 [PlayerService] 尝试备用方案（下载后播放）');
                final tempFilePath = await _downloadAndPlay(songDetail);
                if (tempFilePath != null) {
                  _currentTempFilePath = tempFilePath;
                }
              }
            }
          } else {
            // 本地代理不可用，使用下载后播放
            print('⚠️ [PlayerService] 本地代理不可用，使用备用方案（下载后播放）');
            DeveloperModeService().addLog('⚠️ [PlayerService] 本地代理不可用，使用备用方案（下载后播放）');

            if (platform == 'apple') {
              // Apple Music 不支持“下载后播放”（m3u8 不是音频文件）
              try {
                DeveloperModeService().addLog('🔄 [PlayerService] Apple 尝试直接播放原始 URL');
                await _audioPlayer!.play(ap.UrlSource(songDetail.url));
              } catch (e) {
                if (isStalePlay()) return;
                _state = PlayerState.error;
                _errorMessage = 'Apple Music 播放失败（本地代理不可用且直连失败）';
                notifyListeners();

                // 移动端弹出 Toast 提示
                if (Platform.isAndroid || Platform.isIOS) {
                  ToastUtils.error('播放链接获取失败: $_errorMessage');
                }
                return;
              }
            } else {
              final tempFilePath = await _downloadAndPlay(songDetail);
              if (tempFilePath != null) {
                _currentTempFilePath = tempFilePath;
              }
            }
          }
        }
      } else {
        // 网易云音乐直接播放
        if (_shouldUseMediaKit) {
           await _seekToStart();
           await _mediaKitPlayer!.open(mk.Media(songDetail.url));
           await _mediaKitPlayer!.play();
        } else {
           await _audioPlayer!.play(ap.UrlSource(songDetail.url));
        }
        print('✅ [PlayerService] 开始播放: ${songDetail.url}');
        DeveloperModeService().addLog('✅ [PlayerService] 开始播放网易云音乐');
      }

      // 4. 异步缓存歌曲（不阻塞播放）
      final shouldSkipCache = songDetail.source == MusicSource.apple ||
          songDetail.url.toLowerCase().contains('.m3u8');
      if (!isCached && !shouldSkipCache) {
        _cacheSongInBackground(track, songDetail, qualityStr);
      }
      
      // 5. 后台提取主题色（为播放器页面预加载）
      _extractThemeColorInBackground(songDetail.pic);
    } on AudioSourceNotConfiguredException catch (e) {
      final currentTrack = _currentTrack;
      final currentTrackKey = currentTrack != null
          ? '${currentTrack.source.name}_${currentTrack.id}'
          : null;
      final requestedTrackKey = '${track.source.name}_${track.id}';
      if (currentTrackKey != requestedTrackKey) return;

      // 音源未配置，设置特殊错误状态
      _state = PlayerState.error;
      _errorMessage = e.message;
      _isAudioSourceNotConfigured = true;  // 标记为音源未配置
      print('⚠️ [PlayerService] 音源未配置: ${e.message}');
      print('🔔 [PlayerService] 回调状态: ${onAudioSourceNotConfigured == null ? "未设置" : "已设置"}');
      notifyListeners();
      // 调用回调通知 UI 显示弹窗
      if (onAudioSourceNotConfigured != null) {
        print('🔔 [PlayerService] 正在调用音源未配置回调...');
        onAudioSourceNotConfigured!();
      }

      // 移动端弹出 Toast 提示
      if (Platform.isAndroid || Platform.isIOS) {
        ToastUtils.error('音源未配置: $_errorMessage');
      }
    } catch (e) {
      final currentTrack = _currentTrack;
      final currentTrackKey = currentTrack != null
          ? '${currentTrack.source.name}_${currentTrack.id}'
          : null;
      final requestedTrackKey = '${track.source.name}_${track.id}';
      if (currentTrackKey != requestedTrackKey) return;

      _state = PlayerState.error;
      _errorMessage = '播放失败: $e';
      _isAudioSourceNotConfigured = false;
      print('❌ [PlayerService] 播放异常: $e');
      notifyListeners();

      // 移动端弹出 Toast 提示
      if (Platform.isAndroid || Platform.isIOS) {
        ToastUtils.error('播放异常: $_errorMessage');
      }
    }
  }

  /// 获取服务器代理 URL（用于移动端播放 QQ 音乐和酷狗音乐）
  String _getServerProxyUrl(String originalUrl, String platform) {
    final baseUrl = UrlService().baseUrl;
    final encodedUrl = Uri.encodeComponent(originalUrl);
    return '$baseUrl/audio-proxy/stream?url=$encodedUrl&platform=$platform';
  }

  /// 通过服务器代理下载音频并播放（用于移动端 QQ 音乐和酷狗音乐）
  Future<String?> _downloadViaProxyAndPlay(String proxyUrl, String songName, [String? level]) async {
    try {
      print('📥 [PlayerService] 通过服务器代理下载: $songName (音质: $level)');
      DeveloperModeService().addLog('📥 [PlayerService] 通过服务器代理下载: $songName');
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = AudioQualityService.getExtensionFromLevel(level);
      final tempFilePath = '${tempDir.path}/temp_audio_$timestamp.$extension';
      
      // 通过服务器代理下载（服务器已经处理了 referer 等请求头）
      final response = await http.get(Uri.parse(proxyUrl));
      
      if (response.statusCode == 200) {
        // 保存到临时文件
        final file = File(tempFilePath);
        await file.writeAsBytes(response.bodyBytes);
        print('✅ [PlayerService] 代理下载完成: ${response.bodyBytes.length} bytes');
        DeveloperModeService().addLog('✅ [PlayerService] 代理下载完成: ${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        
        // 播放临时文件
        if (_shouldUseMediaKit) {
             await _mediaKitPlayer!.open(mk.Media(tempFilePath));
             await _mediaKitPlayer!.play();
        } else {
             await _audioPlayer!.play(ap.DeviceFileSource(tempFilePath));
        }
        print('▶️ [PlayerService] 开始播放临时文件');
        DeveloperModeService().addLog('▶️ [PlayerService] 开始播放临时文件');
        
        return tempFilePath;
      } else {
        print('❌ [PlayerService] 代理下载失败: HTTP ${response.statusCode}');
        DeveloperModeService().addLog('❌ [PlayerService] 代理下载失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [PlayerService] 代理下载异常: $e');
      DeveloperModeService().addLog('❌ [PlayerService] 代理下载异常: $e');
      return null;
    }
  }

  /// 下载 Apple Music 解密流到本地临时文件
  /// 解决 audioplayers 直接播放 HTTP 流时无法获取时长的问题
  Future<String?> _downloadAppleDecryptedStream(String streamUrl, dynamic trackId) async {
    try {
      print('📥 [PlayerService] 开始下载 Apple Music 解密流...');
      DeveloperModeService().addLog('📥 [PlayerService] 开始下载 Apple Music 解密流');
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/apple_${trackId}_decrypted.mp3';
      
      // 检查是否已有缓存文件
      final cachedFile = File(tempFilePath);
      if (await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        // 有效文件大小：100KB - 50MB
        if (fileSize > 100 * 1024 && fileSize < 50 * 1024 * 1024) {
          print('✅ [PlayerService] 使用缓存的 Apple Music 文件: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          DeveloperModeService().addLog('✅ [PlayerService] 使用缓存文件: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          return tempFilePath;
        } else {
          // 文件大小异常，删除重新下载
          await cachedFile.delete();
        }
      }
      
      // 下载解密流
      final response = await http.get(
        Uri.parse(streamUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(
        const Duration(minutes: 2), // 解密可能需要较长时间
        onTimeout: () {
          throw TimeoutException('下载超时');
        },
      );
      
      if (response.statusCode == 200) {
        // 保存到临时文件
        final file = File(tempFilePath);
        await file.writeAsBytes(response.bodyBytes);
        final fileSizeMB = (response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2);
        print('✅ [PlayerService] Apple Music 解密流下载完成: $fileSizeMB MB');
        DeveloperModeService().addLog('✅ [PlayerService] 解密流下载完成: $fileSizeMB MB');
        return tempFilePath;
      } else {
        print('❌ [PlayerService] Apple Music 解密流下载失败: HTTP ${response.statusCode}');
        DeveloperModeService().addLog('❌ [PlayerService] 解密流下载失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [PlayerService] Apple Music 解密流下载异常: $e');
      DeveloperModeService().addLog('❌ [PlayerService] 解密流下载异常: $e');
      return null;
    }
  }

  /// 通过 HEAD 请求获取 Apple Music 解密流的时长（毫秒）
  Future<int?> _getAppleStreamDuration(String streamUrl) async {
    try {
      // 发送 HEAD 请求获取响应头
      final request = http.Request('HEAD', Uri.parse(streamUrl));
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('HEAD 请求超时');
          },
        );
        
        // 从响应头获取时长（毫秒）
        final durationMsStr = response.headers['x-duration-ms'];
        if (durationMsStr != null) {
          final durationMs = int.tryParse(durationMsStr);
          if (durationMs != null && durationMs > 0) {
            return durationMs;
          }
        }
        
        // 备用：从 X-Content-Duration（秒）获取
        final durationSecStr = response.headers['x-content-duration'];
        if (durationSecStr != null) {
          final durationSec = double.tryParse(durationSecStr);
          if (durationSec != null && durationSec > 0) {
            return (durationSec * 1000).round();
          }
        }
        
        return null;
      } finally {
        client.close();
      }
    } catch (e) {
      print('⚠️ [PlayerService] 获取 Apple Music 时长失败: $e');
      return null;
    }
  }

  /// 通知用户 Apple Music 歌曲需要换源才能播放
  void _notifyAppleMusicRestriction(Track track) {
    NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: 'Apple Music 播放限制',
      body: '由于Apple接口限制，"${track.name}" 需要换源才能播放！',
    );
    
    // 移动端弹出 Toast 提示
    if (Platform.isAndroid || Platform.isIOS) {
      ToastUtils.error('由于Apple接口限制，该音乐需换源播放');
    }
    print('🍎 [PlayerService] 已发送 Apple Music 换源提示通知');
  }

  /// 下载音频文件并播放（用于QQ音乐和酷狗音乐）
  Future<String?> _downloadAndPlay(SongDetail songDetail) async {
    try {
      print('📥 [PlayerService] 开始下载音频: ${songDetail.name} (音质: ${songDetail.level})');
      DeveloperModeService().addLog('📥 [PlayerService] 开始下载音频: ${songDetail.name}');
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = AudioQualityService.getExtensionFromLevel(songDetail.level);
      final tempFilePath = '${tempDir.path}/temp_audio_$timestamp.$extension';
      
      // 设置请求头（QQ音乐需要 referer）
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };
      if (songDetail.source == MusicSource.qq) {
        headers['referer'] = 'https://y.qq.com';
        print('🔐 [PlayerService] 设置 referer: https://y.qq.com');
        DeveloperModeService().addLog('🔐 [PlayerService] 设置 QQ 音乐 referer');
      } else if (songDetail.source == MusicSource.kugou) {
        headers['referer'] = 'https://www.kugou.com';
        DeveloperModeService().addLog('🔐 [PlayerService] 设置酷狗音乐 referer');
      }
      
      DeveloperModeService().addLog('🔗 [PlayerService] 下载URL: ${songDetail.url.length > 80 ? '${songDetail.url.substring(0, 80)}...' : songDetail.url}');
      
      // 下载音频文件
      final response = await http.get(
        Uri.parse(songDetail.url),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        // 保存到临时文件
        final file = File(tempFilePath);
        await file.writeAsBytes(response.bodyBytes);
        print('✅ [PlayerService] 下载完成: ${response.bodyBytes.length} bytes');
        print('📁 [PlayerService] 临时文件: $tempFilePath');
        DeveloperModeService().addLog('✅ [PlayerService] 下载完成: ${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        
        // 播放临时文件
        if (_shouldUseMediaKit) {
             await _mediaKitPlayer!.open(mk.Media(tempFilePath));
             await _mediaKitPlayer!.play();
        } else {
             await _audioPlayer!.play(ap.DeviceFileSource(tempFilePath));
        }
        print('▶️ [PlayerService] 开始播放临时文件');
        DeveloperModeService().addLog('▶️ [PlayerService] 开始播放临时文件');
        
        return tempFilePath;
      } else {
        print('❌ [PlayerService] 下载失败: HTTP ${response.statusCode}');
        DeveloperModeService().addLog('❌ [PlayerService] 下载失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [PlayerService] 下载音频失败: $e');
      DeveloperModeService().addLog('❌ [PlayerService] 下载音频失败: $e');
      return null;
    }
  }

  /// 后台缓存歌曲
  Future<void> _cacheSongInBackground(
    Track track,
    SongDetail songDetail,
    String quality,
  ) async {
    try {
      print('💾 [PlayerService] 开始后台缓存: ${track.name}');
      await CacheService().cacheSong(track, songDetail, quality);
      print('✅ [PlayerService] 缓存完成: ${track.name}');
    } catch (e) {
      print('⚠️ [PlayerService] 缓存失败: $e');
      // 缓存失败不影响播放
    }
  }

  Future<void> _updateCoverImage(String? imageUrl, {bool notify = true, bool force = false}) async {
    // 调试日志输出调用时机
    // print('🖼️ [PlayerService] _updateCoverImage: $imageUrl (Notify: $notify, Force: $force)');

    if (imageUrl == null || imageUrl.isEmpty) {
      if (_currentCoverImageProvider != null) {
        setCurrentCoverImageProvider(null, shouldNotify: notify);
        _currentCoverUrl = null;
      }
      return;
    }

    // ✅ 关键优化：如果显式提供了 provider 且没有强制要求刷新（针对同一首歌），则锁定封面
    if (!force && _currentCoverImageProvider != null && _currentCoverUrl != null) {
      // 如果 URL 看起来是同一个（简单字符串匹配）或者我们已经锁定了 provider，则直接跳过
      if (_currentCoverUrl == imageUrl) return;
      
      // 进一步优化：即使 URL 字符串不一致，但如果我们正处于“歌曲详情加载”阶段，
      // 且已经有了来自 Track 的封面，通常不需要因为 SongDetail 的 URL 稍有不同而刷新。
      // 这里我们保守一点，只在非 force 情况下拦截。
      return;
    }

    // 更新当前 URL 记录（仅在准备真正创建新的 provider 时）
    _currentCoverUrl = imageUrl;

    try {
      // 判断是网络 URL 还是本地文件路径
      final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
      
      ImageProvider provider;
      if (isNetwork) {
        // 网络图片：使用 CachedNetworkImageProvider
        provider = CachedNetworkImageProvider(imageUrl);
      } else {
        // 本地文件：使用 FileImage
        final file = File(imageUrl);
        if (!await file.exists()) {
          print('⚠️ [PlayerService] 本地封面文件不存在: $imageUrl');
          setCurrentCoverImageProvider(null, shouldNotify: notify);
          return;
        }
        provider = FileImage(file);
      }
      
      // 预热缓存，避免迷你播放器和全屏播放器重复请求
      provider.resolve(const ImageConfiguration());
      setCurrentCoverImageProvider(
        provider,
        shouldNotify: notify,
        imageUrl: imageUrl,
      );
    } catch (e) {
      print('⚠️ [PlayerService] 预加载封面失败: $e');
      setCurrentCoverImageProvider(null, shouldNotify: notify);
    }
  }

  /// 预取下一首歌曲的封面和主题色
  Future<void> _precacheNextCover() async {
    try {
      final nextTrack = PlaylistQueueService().peekNext(PlaybackModeService().currentMode);
      if (nextTrack == null || nextTrack.picUrl.isEmpty) return;

      final imageUrl = nextTrack.picUrl;
      final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
      
      if (isNetwork) {
        print('🖼️ [PlayerService] 预缓存下一首封面: ${nextTrack.name} -> $imageUrl');
        final provider = CachedNetworkImageProvider(imageUrl);
        
        // 检查是否需要预加载主题色
        final backgroundService = PlayerBackgroundService();
        final shouldPrecacheThemeColor = backgroundService.enableGradient && 
            backgroundService.backgroundType == PlayerBackgroundType.adaptive;
        
        // 触发加载
        final ImageStream stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((_, __) {
          print('✅ [PlayerService] 下一首封面预缓存完成: ${nextTrack.name}');
          
          // ✨ 关键修复：封面缓存完成后再提取主题色
          if (shouldPrecacheThemeColor) {
            _precacheNextThemeColor(imageUrl, nextTrack.name);
          }
        }, onError: (dynamic exception, StackTrace? stackTrace) {
          print('⚠️ [PlayerService] 下一首封面预缓存失败: $exception');
        });
        stream.addListener(listener);
      }
    } catch (e) {
      print('⚠️ [PlayerService] 预缓存图片逻辑异常: $e');
    }
  }

  /// 预加载下一首歌曲的主题色（仅缓存，不更新 UI）
  Future<void> _precacheNextThemeColor(String imageUrl, String trackName) async {
    try {
      // 检查是否已经缓存
      final cacheKey = imageUrl;
      if (_themeColorCache.containsKey(cacheKey)) {
        print('🎨 [PlayerService] 下一首主题色已在缓存: $trackName');
        return;
      }

      print('🎨 [PlayerService] 预加载下一首主题色: $trackName');
      
      // 使用 isolate 提取颜色，不阻塞主线程
      final themeColor = await _extractColorFromFullImageAsync(imageUrl);
      
      if (themeColor != null) {
        _themeColorCache[cacheKey] = themeColor;
        print('✅ [PlayerService] 下一首主题色预加载完成: $trackName -> $themeColor');
      } else {
        print('⚠️ [PlayerService] 下一首主题色预加载失败: $trackName');
      }
    } catch (e) {
      print('⚠️ [PlayerService] 预加载主题色异常: $e');
    }
  }

  /// 后台提取主题色（为播放器页面预加载）
  /// 使用 isolate 避免阻塞主线程
  Future<void> _extractThemeColorInBackground(String imageUrl) async {
    if (imageUrl.isEmpty) {
      // 如果没有图片URL，设置一个默认颜色（灰色更柔和）
      themeColorNotifier.value = Colors.grey[700]!;
      return;
    }

    try {
      // 检查缓存
      final backgroundService = PlayerBackgroundService();
      final isMobileGradientMode = Platform.isAndroid && 
                                   backgroundService.enableGradient &&
                                   backgroundService.backgroundType == PlayerBackgroundType.adaptive;
      
      // ✅ 优化：立即从 ColorExtractionService 获取缓存结果（如果有）
      ColorExtractionResult? cachedResult;
      if (isMobileGradientMode) {
        // 模拟底部 30% 区域（这只是为了匹配之前 extractColorsFromRegion 的缓存键生成方式，
        // 实际逻辑中我们现在改为在 extractColorFromBottomRegion 里统一处理）
        // 暂时直接检查 imageUrl 缓存，稍后由异步方法处理
      } else {
        cachedResult = ColorExtractionService().getCachedColors(imageUrl);
      }
      
      if (cachedResult != null && cachedResult.themeColor != null) {
        themeColorNotifier.value = cachedResult.themeColor!;
        print('🎨 [PlayerService] 使用缓存的主题色: ${cachedResult.themeColor}');
        return;
      }

      // ✅ 优化：立即设置默认色，避免UI阻塞
      themeColorNotifier.value = Colors.grey[700]!;

      // ✅ 关键优化：如果应用已经在后台运行，且用户并没有显式查看播放器（已有颜色或不是切换第一首歌），
      // 则可以推迟甚至跳过异步颜色提取，以减少后台 CPU 竞争，防止卡顿。
      final isAppInBackground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
                             WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive;
      
      if (isAppInBackground) {
        print('🎨 [PlayerService] 应用在后台，跳过异步主题色提取以节省资源');
        return;
      }

      print('🎨 [PlayerService] 开始异步提取主题色${isMobileGradientMode ? '（从封面底部）' : ''}...');
      
      Color? themeColor;
      if (isMobileGradientMode) {
        themeColor = await _extractColorFromBottomRegion(imageUrl);
      } else {
        final result = await ColorExtractionService().extractColorsFromUrl(imageUrl);
        themeColor = result?.themeColor;
      }

      // 如果提取成功，更新主题色
      if (themeColor != null) {
        themeColorNotifier.value = themeColor;
        print('✅ [PlayerService] 主题色提取完成: $themeColor');
      }
    } catch (e) {
      print('⚠️ [PlayerService] 主题色提取失败: $e');
    }
  }

  /// 从整张图片提取主题色（使用 isolate，不阻塞主线程）
  /// ✅ 优化：优先从 CachedNetworkImage 的本地缓存读取图片，避免重复下载
  Future<Color?> _extractColorFromFullImageAsync(String imageUrl) async {
    try {
      // 优先使用本地缓存的图片（封面已被预加载到缓存）
      final result = await ColorExtractionService().extractColorsFromCachedImage(
        imageUrl,
        sampleSize: 64, // 主题色使用稍大的尺寸以获取更准确的颜色
        timeout: const Duration(seconds: 3),
      );
      
      return result?.themeColor;
    } catch (e) {
      print('⚠️ [PlayerService] 提取颜色异常: $e');
      return null;
    }
  }

  /// 从图片底部区域提取主题色（使用 Isolate 异步提取，不阻塞主线程）
  Future<Color?> _extractColorFromBottomRegion(String imageUrl) async {
    try {
      // ✅ 关键优化：预定义底部区域（底部 30%）
      // 由于我们不知道图片的原始尺寸，且不想在主线程解码，
      // 我们在 ColorExtractionService 中处理这个问题。
      // 为简化，我们传递一个较大的虚拟尺寸，Isolate 内部会自动处理。
      // 但其实更简单的方法是让 ColorExtractionService 内部自己计算底部。
      
      // 这里的 Rect 是相对于原始图片的坐标。因为我们现在不知道图片大小，
      // 我们修改了 ColorExtractionService 支持直接指定“底部比例”。
      // 既然目前的 Service 还不支持比例，我们先手动读取一次尺寸（很快）或者
      // 直接在 Isolate 中解码后进行裁剪。
      
      // 注意：目前的 ColorExtractionService 已经支持了 Rect 裁剪。
      // 为了性能，我们这里的解决方案是发送一个特殊的 Rect，
      // 如果 rect.left 是 -1，表示按比例提取底部。
      // 或者：直接在这里先用轻量级的手段获取图片尺寸。
      
      // 最简单稳定的方案：更新 ColorExtractionService 以便在不知道尺寸时也能处理比例。
      // 既然已经实施了 Rect 裁剪，我们先在 PlayerService 逻辑中保持简洁。
      
      // 🔧 改进：直接让 ColorExtractionService 处理底部 30% 的逻辑
      // 这里我们先传递一个“标志位”区域，或者就在 Isolate 里面写死 30%。
      // 咱们还是把逻辑做在 ColorExtractionService 比较干净。
      
      // 临时方案（为了不再次修改 Service）：
      // 先用一个大概的 Rect，或者修改 Service 增加 extractColorsFromBottomFraction。
      
      // 💡 更好方案：使用我们刚才新建好的 extractColorsFromRegion。
      // 我们在内部先快速 Resolve 图片获取尺寸（这在主线程完成，但通常很快）
      final ImageProvider imageProvider = imageUrl.startsWith('http') 
          ? CachedNetworkImageProvider(imageUrl) 
          : FileImage(File(imageUrl));
      
      final async_lib.Completer<ui.Image> completer = async_lib.Completer();
      final ImageStream stream = imageProvider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
         completer.complete(info.image);
         stream.removeListener(listener);
      }, onError: (e, s) {
         completer.completeError(e, s);
         stream.removeListener(listener);
      });
      stream.addListener(listener);
      
      final image = await completer.future.timeout(const Duration(seconds: 3));
      final region = Rect.fromLTWH(0, image.height * 0.7, image.width.toDouble(), image.height * 0.3);
      
      final result = await ColorExtractionService().extractColorsFromRegion(
        imageUrl,
        region: region,
        sampleSize: 64,
      );
      
      return result?.themeColor;
    } catch (e) {
      print('⚠️ [PlayerService] 异步从底部区域提取颜色失败: $e');
      return null;
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      if (_useMediaKit && _mediaKitPlayer != null) {
        await _mediaKitPlayer!.pause();
      } else if (_audioPlayer != null) {
        await _audioPlayer!.pause();
      }
      _pauseListeningTimeTracking();
      print('⏸️ [PlayerService] 暂停播放');
    } catch (e) {
      print('❌ [PlayerService] 暂停失败: $e');
    }
  }

  /// 继续播放
  Future<void> resume() async {
    // 预载态：播放器尚未初始化，需走完整播放流程
    if (_state == PlayerState.idle && _currentTrack != null &&
        _audioPlayer == null && _mediaKitPlayer == null) {
      await playTrack(_currentTrack!);
      return;
    }

    try {
      if (_useMediaKit && _mediaKitPlayer != null) {
        await _mediaKitPlayer!.play();
      } else if (_audioPlayer != null) {
        await _audioPlayer!.resume();
      }
      _startListeningTimeTracking();
      print('▶️ [PlayerService] 继续播放');
    } catch (e) {
      print('❌ [PlayerService] 继续播放失败: $e');
    }
  }

  /// 停止
  Future<void> stop() async {
    try {
      if (_useMediaKit && _mediaKitPlayer != null) {
        await _mediaKitPlayer!.stop();
      } else if (_audioPlayer != null) {
        await _audioPlayer!.stop();
      }

      // 清理临时文件
      await _cleanupCurrentTempFile();

      // 停止听歌时长追踪
      _pauseListeningTimeTracking();

      _state = PlayerState.idle;
      _currentSong = null;
      _currentTrack = null;
      _errorMessage = null;
      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero; // 重置进度通知器
      setCurrentCoverImageProvider(null, shouldNotify: false);
      notifyListeners();
      print('⏹️ [PlayerService] 停止播放');
    } catch (e) {
      print('❌ [PlayerService] 停止失败: $e');
    }
  }
  
  /// 媒体尝试 Seek 到开始位置 (MediaKit 专用 helper)
  Future<void> _seekToStart() async {
     if (_mediaKitPlayer != null) {
       // 防止某些情况下 MediaKit 记住上次播放位置导致不从头开始
       try {
         await _mediaKitPlayer!.seek(Duration.zero);
       } catch (_) {}
     }
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    try {
      if (_useMediaKit && _mediaKitPlayer != null) {
        await _mediaKitPlayer!.seek(position);
      } else if (_audioPlayer != null) {
        await _audioPlayer!.seek(position);
      }
      _position = position;
      positionNotifier.value = position;
      // 强制立即同步到原生层
      _syncPositionToNative(position, force: true);
      print('⏩ [PlayerService] 跳转到: ${position.inSeconds}s');
    } catch (e) {
      print('❌ [PlayerService] 跳转失败: $e');
    }
  }

  /// 节流同步位置到 Android 原生层
  void _syncPositionToNative(Duration position, {bool force = false}) {
    if (!Platform.isAndroid) return;
    
    final now = DateTime.now();
    // 正常播放时每 500ms 同步一次，seek 时强制同步
    if (force || now.difference(_lastNativeSyncTime).inMilliseconds > 500) {
      AndroidFloatingLyricService().updatePosition(position);
      _lastNativeSyncTime = now;
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    try {
      final clampedVolume = volume.clamp(0.0, 1.0);
      
      // 🔧 性能优化：增加音量变化检测 (epsilon = 0.001)
      // 如果音量变化微乎其微，则跳过后续操作，减少通知和 I/O
      if ((clampedVolume - _volume).abs() < 0.001) return;
      
      _volume = clampedVolume;

      // 只有在播放器已初始化时才应用音量
      if (_useMediaKit && _mediaKitPlayer != null) {
        await _mediaKitPlayer!.setVolume(clampedVolume * 100);
      } else if (_audioPlayer != null) {
        await _audioPlayer!.setVolume(clampedVolume);
      }

      _saveVolumeThrottled(); // 🔧 性能优化：使用节约流方式保存音量设置
      notifyListeners(); // 通知监听器音量已改变
      print('🔊 [PlayerService] 音量设置为: ${(clampedVolume * 100).toInt()}%');
    } catch (e) {
      print('⚠️ [PlayerService] 设置音量失败: $e');
    }
  }

  async_lib.Timer? _saveVolumeTimer;
  /// 节流方式保存音量，避免在连续调节音量时频繁触发磁盘写入
  void _saveVolumeThrottled() {
    _saveVolumeTimer?.cancel();
    _saveVolumeTimer = async_lib.Timer(const Duration(milliseconds: 1000), () {
      _saveVolume();
    });
  }

  /// 保存音量设置
  Future<void> _saveVolume() async {
    try {
      await PersistentStorageService().setDouble('player_volume', _volume);
    } catch (e) {
      print('❌ [PlayerService] 保存音量失败: $e');
    }
  }


  Future<void> _ensureMediaKitPlayer() async {
    if (_mediaKitPlayer != null) return;
    _mediaKitPlayer = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'Cyrene Music',
        ready: null,
      ),
    );

    // 🔧 性能优化：针对 Android 后台播放优化缓冲策略
    if (Platform.isAndroid) {
      try {
        // 设置音频缓冲区大小（秒），默认通常很小
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('audio-buffer', '10.0');
        // 开启缓存并设置缓冲区大小 (10MB)
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('cache', 'yes');
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('demuxer-max-bytes', '10485760');
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('demuxer-max-back-bytes', '5242880');
        // 设置预读时长
        await (_mediaKitPlayer!.platform as dynamic)?.setProperty('demuxer-readahead-secs', '30');
        print('🚀 [PlayerService] MediaKit Android 后台优化参数已应用');
      } catch (e) {
        print('⚠️ [PlayerService] MediaKit 优化参数应用失败: $e');
      }
    }
    
    // 初始化完成后，注入播放器引用并应用均衡器
    EqualizerService().setPlayer(_mediaKitPlayer, useMediaKit: _useMediaKit);
    await EqualizerService().applyEqualizer();

    // 立即应用音量设置，避免首次播放以默认100%音量出声
    await _mediaKitPlayer!.setVolume(_volume * 100);
    print('🔊 [PlayerService] MediaKit 已应用音量设置: ${(_volume * 100).toInt()}%');

    _mediaKitPlayingSub = _mediaKitPlayer!.stream.playing.listen((playing) {
      if (playing) {
        _state = PlayerState.playing;
        _startListeningTimeTracking();
        _startStateSaveTimer();
        if (Platform.isWindows) {
          DesktopLyricService().setPlayingState(true);
        }
        if (Platform.isAndroid) {
          AndroidFloatingLyricService().setPlayingState(true);
        }
      } else {
        if (_state == PlayerState.playing) {
          _state = PlayerState.paused;
          _pauseListeningTimeTracking();
          _saveCurrentPlaybackState();
          _stopStateSaveTimer();
          if (Platform.isWindows) {
            DesktopLyricService().setPlayingState(false);
          }
          if (Platform.isAndroid) {
            AndroidFloatingLyricService().setPlayingState(false);
          }
        }
      }
      notifyListeners();
    });

    _mediaKitPositionSub = _mediaKitPlayer!.stream.position.listen((position) {
      _position = position;
      positionNotifier.value = position; // 更新独立的进度通知器
      _updateFloatingLyric();
      // 🔧 性能优化：不再在进度更新时调用 notifyListeners()，避免全国范围的 UI 重建
      // notifyListeners(); 
    });

    _mediaKitDurationSub = _mediaKitPlayer!.stream.duration.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });

    _mediaKitCompletedSub = _mediaKitPlayer!.stream.completed.listen((completed) {
      if (completed) {
        _state = PlayerState.idle;
        _position = Duration.zero;
        _pauseListeningTimeTracking();
        _stopStateSaveTimer();
        if (Platform.isWindows) {
          DesktopLyricService().setPlayingState(false);
        }
        if (Platform.isAndroid) {
          AndroidFloatingLyricService().setPlayingState(false);
        }
        notifyListeners();
        _playNextFromHistory();
      }
    });
  }

  Future<void> _playAppleWithMediaKit(SongDetail songDetail) async {
    await _ensureMediaKitPlayer();
    _useMediaKit = true;

    try {
      // 避免与 audioplayers 同时占用设备
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
      }
    } catch (_) {}

    final proxyReady = await _ensureLocalProxyRunning('apple');
    final url = proxyReady
        ? ProxyService().getProxyUrl(songDetail.url, 'apple')
        : songDetail.url;

    _state = PlayerState.loading;
    notifyListeners();

    await _mediaKitPlayer!.setVolume(_volume * 100);
    await _mediaKitPlayer!.open(mk.Media(url));
    await _mediaKitPlayer!.play();
  }

  Future<bool> _ensureLocalProxyRunning(String platform) async {
    if (ProxyService().isRunning) return true;

    DeveloperModeService().addLog('🌐 [PlayerService] 尝试启动本地代理服务器...');
    final started = await ProxyService().start();
    if (started) {
      DeveloperModeService().addLog('✅ [PlayerService] 本地代理服务器已就绪 (端口: ${ProxyService().port})');
    } else {
      DeveloperModeService().addLog('⚠️ [PlayerService] 本地代理服务器启动失败，将使用备用方案');
    }
    return started;
  }

  /// 播放网络电台流
  Future<void> playRadioStream(String streamUrl, Track radioTrack) async {
    try {
      await _ensurePlayerInitialized();
      _useMediaKit = _shouldUseMediaKit;

      // 清理上一首的临时文件
      await _cleanupCurrentTempFile();

      _state = PlayerState.loading;
      _currentTrack = radioTrack;
      _currentSong = null;
      _errorMessage = null;
      ++_playGeneration; // 电台播放也递增代数
      _duration = Duration.zero;
      _position = Duration.zero;
      positionNotifier.value = Duration.zero;

      // 清空封面
      _currentCoverImageProvider = null;
      _currentCoverUrl = null;
      themeColorNotifier.value = null;

      notifyListeners();

      print('📻 [PlayerService] 播放电台流: $streamUrl');

      if (_shouldUseMediaKit) {
        await _mediaKitPlayer!.setVolume(_volume * 100);
        await _mediaKitPlayer!.open(mk.Media(streamUrl));
        await _mediaKitPlayer!.play();
      } else {
        await _audioPlayer!.play(ap.UrlSource(streamUrl));
      }

      _state = PlayerState.playing;
      _startListeningTimeTracking();
      notifyListeners();

      print('✅ [PlayerService] 电台播放开始: ${radioTrack.name}');
    } catch (e, st) {
      print('❌ [PlayerService] 电台播放失败: $e');
      print('❌ [PlayerService] Stack: $st');
      _state = PlayerState.error;
      _errorMessage = '电台播放失败: $e';
      notifyListeners();
    }
  }

  /// 预载轨道（不播放）：设置 currentTrack 和封面，使 MiniPlayer 以暂停态显示。
  /// 用于启动时加载队列后让用户一键播放。
  Future<void> preloadTrack(Track track, {ImageProvider? coverProvider}) async {
    if (_currentTrack != null) return; // 已有轨道，不覆盖

    _currentTrack = track;
    _state = PlayerState.idle;
    _duration = Duration.zero;
    _position = Duration.zero;

    if (coverProvider != null) {
      setCurrentCoverImageProvider(coverProvider, shouldNotify: false, imageUrl: track.picUrl);
    } else {
      await _updateCoverImage(track.picUrl, notify: false, force: true);
    }

    print('🎵 [PlayerService] 已预载轨道: ${track.name}');
    notifyListeners();
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await resume(); // resume() 内部已处理预载态
    }
  }

  /// 清理当前临时文件
  Future<void> _cleanupCurrentTempFile() async {
    if (_currentTempFilePath != null) {
      try {
        final tempFile = File(_currentTempFilePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
          print('🧹 [PlayerService] 已删除临时文件: $_currentTempFilePath');
        }
      } catch (e) {
        print('⚠️ [PlayerService] 删除临时文件失败: $e');
      } finally {
        _currentTempFilePath = null;
      }
    }
  }

  /// 开始听歌时长追踪
  void _startListeningTimeTracking() {
    // 如果已经在追踪，不重复启动
    if (_statsTimer != null && _statsTimer!.isActive) return;
    
    _playStartTime = DateTime.now();
    
    // 每5秒记录一次听歌时长
    _statsTimer = async_lib.Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_playStartTime != null) {
        final now = DateTime.now();
        final elapsed = now.difference(_playStartTime!).inSeconds;
        
        if (elapsed > 0) {
          _sessionListeningTime += elapsed;
          ListeningStatsService().accumulateListeningTime(elapsed);
          _playStartTime = now;
          
          print('📊 [PlayerService] 累积听歌时长: +${elapsed}秒 (会话总计: ${_sessionListeningTime}秒)');
        }
      }
    });
    
    print('📊 [PlayerService] 开始听歌时长追踪');
  }
  
  /// 暂停听歌时长追踪
  void _pauseListeningTimeTracking() {
    if (_statsTimer != null) {
      // 在停止定时器前，记录最后一段时间
      if (_playStartTime != null) {
        final now = DateTime.now();
        final elapsed = now.difference(_playStartTime!).inSeconds;
        
        if (elapsed > 0) {
          _sessionListeningTime += elapsed;
          ListeningStatsService().accumulateListeningTime(elapsed);
          print('📊 [PlayerService] 累积听歌时长: +${elapsed}秒 (会话总计: ${_sessionListeningTime}秒)');
        }
      }
      
      _statsTimer?.cancel();
      _statsTimer = null;
      _playStartTime = null;
      print('📊 [PlayerService] 暂停听歌时长追踪');
    }
  }

  /// 开始定期保存播放状态定时器
  void _startStateSaveTimer() {
    // 如果已经在运行，不重复启动
    if (_stateSaveTimer != null && _stateSaveTimer!.isActive) return;

    // 如果用户关闭了恢复播放提示，不启动定时器，节省 I/O
    if (!AppSettingsService().showResumePromptOnStartup) return;

    // 每10秒保存一次播放状态
    _stateSaveTimer = async_lib.Timer.periodic(const Duration(seconds: 10), (timer) {
      _saveCurrentPlaybackState();
    });

    print('💾 [PlayerService] 开始定期保存播放状态（每10秒）');
  }

  /// 停止保存播放状态定时器
  void _stopStateSaveTimer() {
    if (_stateSaveTimer != null) {
      _stateSaveTimer?.cancel();
      _stateSaveTimer = null;
      print('💾 [PlayerService] 停止定期保存播放状态');
    }
  }

  /// 保存当前播放状态
  void _saveCurrentPlaybackState() {
    // 如果用户关闭了恢复播放提示，跳过保存
    if (!AppSettingsService().showResumePromptOnStartup) return;

    if (_currentTrack == null || _state != PlayerState.playing) {
      return;
    }

    // 如果播放位置小于5秒，不保存（刚开始播放）
    if (_position.inSeconds < 5) {
      return;
    }

    // 检查是否是从播放队列播放的
    final isFromPlaylist = PlaylistQueueService().hasQueue;

    PlaybackStateService().savePlaybackState(
      track: _currentTrack!,
      position: _position,
      isFromPlaylist: isFromPlaylist,
    );
  }

  /// 清理资源
  @override
  void dispose() {
    print('🗑️ [PlayerService] 释放播放器资源...');
    // 停止统计定时器
    _pauseListeningTimeTracking();
    // 停止状态保存定时器
    _stopStateSaveTimer();
    // 同步清理当前临时文件
    _cleanupCurrentTempFile();
    // 只有在 AudioPlayer 已初始化时才释放
    if (_audioPlayer != null) {
      _audioPlayer!.stop();
      _audioPlayer!.dispose();
    }
    // 释放 MediaKit 播放器
    if (_mediaKitPlayer != null) {
      _mediaKitPlayer!.dispose();
      _mediaKitPlayer = null;
    }
    // 停止代理服务器
    ProxyService().stop();
    // 清理主题色通知器
    themeColorNotifier.dispose();
    super.dispose();
  }

  /// 强制释放所有资源（用于应用退出时）
  Future<void> forceDispose() async {
    try {
      print('🗑️ [PlayerService] 强制释放播放器资源...');

      // 清理当前播放的临时文件
      await _cleanupCurrentTempFile();

      // 清理所有临时缓存文件
      await CacheService().cleanTempFiles();

      // 停止代理服务器
      await ProxyService().stop();

      // 先移除所有监听器，防止状态改变时触发通知
      print('🔌 [PlayerService] 移除所有监听器...');
      // 注意：这里不能直接访问 _listeners，因为 ChangeNotifier 不暴露它
      // 但是我们可以通过设置一个标志来阻止 notifyListeners 生效

      // 立即清理状态（不触发通知）
      _state = PlayerState.idle;
      _currentSong = null;
      _currentTrack = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      setCurrentCoverImageProvider(null, shouldNotify: false);

      // 只有在 AudioPlayer 已初始化时才释放
      if (_audioPlayer != null) {
        // 使用 unawaited 方式，不等待完成，直接继续
        // 因为应用即将退出，操作系统会自动清理资源
        _audioPlayer!.stop().catchError((e) {
          print('⚠️ [PlayerService] 停止播放失败: $e');
        });

        _audioPlayer!.dispose().catchError((e) {
          print('⚠️ [PlayerService] 释放资源失败: $e');
        });
      }
      
      // 释放 MediaKit 播放器
      if (_mediaKitPlayer != null) {
        _mediaKitPlayer!.dispose();
        _mediaKitPlayer = null;
      }

      print('✅ [PlayerService] 播放器资源清理指令已发出');
    } catch (e) {
      print('❌ [PlayerService] 释放资源失败: $e');
    }
  }

  /// 播放完毕后自动播放下一首（根据播放模式）
  Future<void> _playNextFromHistory() async {
    try {
      print('⏭️ [PlayerService] 歌曲播放完毕，检查播放模式...');
      
      final mode = PlaybackModeService().currentMode;
      
      switch (mode) {
        case PlaybackMode.repeatOne:
          // 单曲循环：重新播放当前歌曲
          if (_currentTrack != null) {
            print('🔂 [PlayerService] 单曲循环，重新播放当前歌曲');
            await Future.delayed(const Duration(milliseconds: 500));
            await playTrack(
              _currentTrack!,
              coverProvider: _currentCoverImageProvider,
            );
          }
          break;
          
        case PlaybackMode.sequential:
          // 顺序播放：播放历史中的下一首
          await _playNext();
          break;
          
        case PlaybackMode.shuffle:
          // 随机播放：从历史中随机选一首
          await _playRandomFromHistory();
          break;
      }
    } catch (e) {
      print('❌ [PlayerService] 自动播放下一首失败: $e');
    }
  }

  /// 清除当前播放会话
  Future<void> clearSession() async {
    print('🗑️ [PlayerService] 清除播放会话...');

    // 停止播放（只有在播放器已初始化时）
    if (_audioPlayer != null) {
      await _audioPlayer!.stop();
    }

    // 清除状态
    _state = PlayerState.idle;
    _currentSong = null;
    _currentTrack = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _errorMessage = null;
    _currentCoverImageProvider = null;
    _currentCoverUrl = null;
    themeColorNotifier.value = null;

    // 清除临时文件
    await _cleanupCurrentTempFile();

    // 停止计时器
    _stopStateSaveTimer();
    _pauseListeningTimeTracking();

    // 清除通知
    // 注意：这可能需要在 NotificationService 中处理

    // 更新UI
    notifyListeners();

    // 🔥 通知Android原生层
    if (Platform.isAndroid) {
      AndroidFloatingLyricService().setPlayingState(false);
      AndroidFloatingLyricService().updatePosition(Duration.zero);
    }

    print('✅ [PlayerService] 播放会话已清除');
  }

  /// 播放下一首（顺序播放模式）
  Future<void> playNext() async {
    final mode = PlaybackModeService().currentMode;
    
    if (mode == PlaybackMode.shuffle) {
      await _playRandomFromHistory();
    } else {
      await _playNext();
    }
  }

  /// 内部方法：播放下一首
  Future<void> _playNext() async {
    try {
      print('⏭️ [PlayerService] 尝试播放下一首...');
      
      // 优先使用播放队列
      if (PlaylistQueueService().hasQueue) {
        final nextTrack = PlaylistQueueService().getNext();
        if (nextTrack != null) {
          print('✅ [PlayerService] 从播放队列获取下一首: ${nextTrack.name}');
          await Future.delayed(const Duration(milliseconds: 500));
          final coverProvider = PlaylistQueueService().getCoverProvider(nextTrack);
          // 如果队列来源是歌单，传递 fromPlaylist: true
          final isFromPlaylist = PlaylistQueueService().source == QueueSource.playlist;
          await playTrack(nextTrack, coverProvider: coverProvider, fromPlaylist: isFromPlaylist);
          return;
        } else {
          print('ℹ️ [PlayerService] 队列已播放完毕，清空队列');
          PlaylistQueueService().clear();
        }
      }
      
      // 如果没有队列，使用播放历史（不检查换源限制）
      final nextTrack = PlayHistoryService().getNextTrack();
      
      if (nextTrack != null) {
        print('✅ [PlayerService] 从播放历史获取下一首: ${nextTrack.name}');
        await Future.delayed(const Duration(milliseconds: 500));
        final coverProvider = PlaylistQueueService().getCoverProvider(nextTrack);
        await playTrack(nextTrack, coverProvider: coverProvider);
      } else {
        print('ℹ️ [PlayerService] 没有更多歌曲可播放');
      }
    } catch (e) {
      print('❌ [PlayerService] 播放下一首失败: $e');
    }
  }

  /// 播放上一首
  Future<void> playPrevious() async {
    try {
      print('⏮️ [PlayerService] 尝试播放上一首...');
      
      final mode = PlaybackModeService().currentMode;
      
      // 优先使用播放队列
      if (PlaylistQueueService().hasQueue) {
        Track? previousTrack;
        
        // 随机模式下使用洗牌序列的上一首
        if (mode == PlaybackMode.shuffle) {
          previousTrack = PlaylistQueueService().getRandomPrevious();
        } else {
          previousTrack = PlaylistQueueService().getPrevious();
        }
        
        if (previousTrack != null) {
          print('✅ [PlayerService] 从播放队列获取上一首: ${previousTrack.name}');
          final coverProvider = PlaylistQueueService().getCoverProvider(previousTrack);
          // 如果队列来源是歌单，传递 fromPlaylist: true
          final isFromPlaylist = PlaylistQueueService().source == QueueSource.playlist;
          await playTrack(previousTrack, coverProvider: coverProvider, fromPlaylist: isFromPlaylist);
          return;
        }
      }
      
      // 如果没有队列，使用播放历史
      final history = PlayHistoryService().history;
      
      // 当前歌曲在历史记录的第0位，上一首在第2位（第1位是当前歌曲之前播放的）
      if (history.length >= 3) {
        final previousTrack = history[2].toTrack();
        print('✅ [PlayerService] 从播放历史获取上一首: ${previousTrack.name}');
        final coverProvider = PlaylistQueueService().getCoverProvider(previousTrack);
        await playTrack(previousTrack, coverProvider: coverProvider);
      } else {
        print('ℹ️ [PlayerService] 没有上一首可播放');
      }
    } catch (e) {
      print('❌ [PlayerService] 播放上一首失败: $e');
    }
  }

  /// 随机播放：从队列或历史中随机选一首
  Future<void> _playRandomFromHistory() async {
    try {
      print('🔀 [PlayerService] 随机播放模式');
      
      // 优先使用播放队列
      if (PlaylistQueueService().hasQueue) {
        final randomTrack = PlaylistQueueService().getRandomTrack();
        if (randomTrack != null) {
          print('✅ [PlayerService] 从播放队列随机选择: ${randomTrack.name}');
          await Future.delayed(const Duration(milliseconds: 500));
          final coverProvider = PlaylistQueueService().getCoverProvider(randomTrack);
          // 如果队列来源是歌单，传递 fromPlaylist: true
          final isFromPlaylist = PlaylistQueueService().source == QueueSource.playlist;
          await playTrack(randomTrack, coverProvider: coverProvider, fromPlaylist: isFromPlaylist);
          return;
        }
      }
      
      // 如果没有队列，使用播放历史
      final history = PlayHistoryService().history;
      
      if (history.length >= 2) {
        // 排除当前歌曲（第0位），从其他歌曲中随机选择
        final random = Random();
        final randomIndex = random.nextInt(history.length - 1) + 1;
        final randomTrack = history[randomIndex].toTrack();
        
        print('✅ [PlayerService] 从播放历史随机选择: ${randomTrack.name}');
        await Future.delayed(const Duration(milliseconds: 500));
        final coverProvider = PlaylistQueueService().getCoverProvider(randomTrack);
        await playTrack(randomTrack, coverProvider: coverProvider);
      } else {
        print('ℹ️ [PlayerService] 历史记录不足，无法随机播放');
      }
    } catch (e) {
      print('❌ [PlayerService] 随机播放失败: $e');
    }
  }

  /// 检查是否有上一首
  bool get hasPrevious {
    // 优先检查播放队列
    if (PlaylistQueueService().hasQueue) {
      return PlaylistQueueService().hasPrevious;
    }
    // 否则检查播放历史
    return PlayHistoryService().history.length >= 3;
  }

  /// 检查是否有下一首
  bool get hasNext {
    // 优先检查播放队列
    if (PlaylistQueueService().hasQueue) {
      return PlaylistQueueService().hasNext;
    }
    // 否则检查播放历史
    return PlayHistoryService().history.length >= 2;
  }

  /// 加载桌面/悬浮歌词（Windows/Android平台）
  void _loadLyricsForFloatingDisplay() {
    final currentSong = _currentSong;
    final currentTrack = _currentTrack;
    
    // 更新桌面歌词的歌曲信息（Windows）
    if (Platform.isWindows && DesktopLyricService().isVisible && currentTrack != null) {
      DesktopLyricService().setSongInfo(
        title: currentTrack.name,
        artist: currentTrack.artists,
        albumCover: currentTrack.picUrl,
      );
    }
    
    if (currentSong == null || currentSong.lyric.isEmpty) {
      print('📝 [PlayerService] 悬浮歌词：无歌词可显示');
      _lyrics = [];
      _currentLyricIndex = -1;
      
      // 清空歌词显示
      if (Platform.isWindows && DesktopLyricService().isVisible) {
        DesktopLyricService().setLyricText('');
      }
      if (Platform.isAndroid && AndroidFloatingLyricService().isVisible) {
        AndroidFloatingLyricService().setLyricText('');
        AndroidFloatingLyricService().setLyricsData([]); // 清空原生层歌词数据
      }
      return;
    }

    try {
      // 根据音乐来源选择不同的解析器
      switch (currentSong.source.name) {
        case 'netease':
          _lyrics = LyricParser.parseNeteaseLyric(
            currentSong.lyric,
            translation: currentSong.tlyric.isNotEmpty ? currentSong.tlyric : null,
            yrcLyric: currentSong.yrc.isNotEmpty ? currentSong.yrc : null,
            yrcTranslation: currentSong.ytlrc.isNotEmpty ? currentSong.ytlrc : null,
          );
          break;
        case 'qq':
          _lyrics = LyricParser.parseQQLyric(
            currentSong.lyric,
            translation: currentSong.tlyric.isNotEmpty ? currentSong.tlyric : null,
            qrcLyric: currentSong.qrc.isNotEmpty ? currentSong.qrc : null,
            qrcTranslation: currentSong.qrcTrans.isNotEmpty ? currentSong.qrcTrans : null,
          );
          break;
        case 'kugou':
          _lyrics = LyricParser.parseKugouLyric(
            currentSong.lyric,
            translation: currentSong.tlyric.isNotEmpty ? currentSong.tlyric : null,
          );
          break;
        default:
          _lyrics = LyricParser.parseNeteaseLyric(
            currentSong.lyric,
            translation: currentSong.tlyric.isNotEmpty ? currentSong.tlyric : null,
            yrcLyric: currentSong.yrc.isNotEmpty ? currentSong.yrc : null,
            yrcTranslation: currentSong.ytlrc.isNotEmpty ? currentSong.ytlrc : null,
          );
      }

      _currentLyricIndex = -1;
      print('🎵 [PlayerService] 悬浮歌词已加载: ${_lyrics.length} 行');
      
      // 🔥 关键优化：异步分发歌词数据到 Android 原生层
      // 避免在播放启动的关键帧进行大规模对象序列化，造成卡顿
      if (Platform.isAndroid && AndroidFloatingLyricService().isVisible) {
        Future.microtask(() {
          final lyricsData = _lyrics.map((line) => {
            'time': line.startTime.inMilliseconds,
            'text': line.text,
            'translation': line.translation ?? '',
          }).toList();
          
          AndroidFloatingLyricService().setLyricsData(lyricsData);
          print('✅ [PlayerService] 歌词数据已异步发送到 Android 原生层');
        });
      }
      
      // 立即更新当前歌词
      _updateFloatingLyric();
    } catch (e) {
      print('❌ [PlayerService] 悬浮歌词加载失败: $e');
      _lyrics = [];
      _currentLyricIndex = -1;
    }
  }

  /// 更新桌面/悬浮歌词显示
  void _updateFloatingLyric() {
    if (_lyrics.isEmpty) return;
    
    // 检查是否有可见的歌词服务
    final isWindowsVisible = Platform.isWindows && DesktopLyricService().isVisible;
    final isAndroidVisible = Platform.isAndroid && AndroidFloatingLyricService().isVisible;
    
    if (!isWindowsVisible && !isAndroidVisible) return;

    try {
      final newIndex = LyricParser.findCurrentLineIndex(_lyrics, _position);

      if (newIndex != _currentLyricIndex && newIndex >= 0) {
        _currentLyricIndex = newIndex;
        final currentLine = _lyrics[newIndex];
        
        // 计算当前歌词行的持续时间（毫秒）
        int? durationMs;
        if (newIndex + 1 < _lyrics.length) {
          // 下一行歌词的时间减去当前行的时间
          durationMs = _lyrics[newIndex + 1].startTime.inMilliseconds - currentLine.startTime.inMilliseconds;
        } else {
          // 最后一行歌词，使用默认3秒
          durationMs = 3000;
        }
        
        // 更新Windows桌面歌词（分别发送歌词和翻译）
        if (isWindowsVisible) {
          DesktopLyricService().setLyricText(currentLine.text, durationMs: durationMs);
          // 发送翻译文本（如果有）
          if (currentLine.translation != null && currentLine.translation!.isNotEmpty) {
            DesktopLyricService().setTranslationText(currentLine.translation!);
          } else {
            DesktopLyricService().setTranslationText('');
          }
        }
        
        // 更新Android悬浮歌词（保持原有逻辑，合并显示）
        if (isAndroidVisible) {
          String displayText = currentLine.text;
          if (currentLine.translation != null && currentLine.translation!.isNotEmpty) {
            displayText = '${currentLine.text}\n${currentLine.translation}';
          }
          AndroidFloatingLyricService().setLyricText(displayText);
        }
      }
    } catch (e) {
      // 忽略更新错误，不影响播放
      print('⚠️ [PlayerService] 悬浮歌词更新失败: $e');
    }
  }
  
  /// 手动更新悬浮歌词（供后台服务调用）
  ///
  /// 这个方法由 AudioHandler 的定时器调用，确保即使应用在后台，
  /// 悬浮歌词也能持续更新
  Future<void> updateFloatingLyricManually() async {
    // 只有在播放器已初始化时才更新
    if (_audioPlayer == null && _mediaKitPlayer == null) return;
    
    // 如果使用 MediaKit，直接同步当前状态位置，不需要 polling 
    if (_useMediaKit && _mediaKitPlayer != null) {
        _syncPositionToNative(_position);
        return;
    }

    // 🔥 关键修复：主动获取播放器的当前位置，而不是依赖 onPositionChanged 事件
    // 因为在后台时，onPositionChanged 事件可能被系统节流或延迟
    try {
      final currentPos = await _audioPlayer!.getCurrentPosition();
      if (currentPos != null) {
        _position = currentPos;

        // 同步位置到原生层，让原生层可以基于最新的位置进行自动推进
        _syncPositionToNative(_position);
      }
    } catch (e) {
      // 忽略获取位置失败的错误，使用缓存的位置
    }

    // 🔥 性能优化：移除冗余的 _updateFloatingLyric() 调用
    // _syncPositionToNative 已经将位置同步到了原生层，原生层具有自推进机制。
    // 在后台时重复调用 _updateFloatingLyric 会导致不必要的 MethodChannel 消息和 UI 刷新开销。
    // _updateFloatingLyric();
  }

  /// 从保存的状态恢复播放
  Future<void> resumeFromSavedState(PlaybackState state) async {
    try {
      print('🔄 [PlayerService] 从保存的状态恢复播放: ${state.track.name}');
      
      // 播放歌曲
      await playTrack(state.track);
      
      // 等待播放开始
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 跳转到保存的位置
      if (state.position.inSeconds > 0) {
        await seek(state.position);
        print('⏩ [PlayerService] 已跳转到保存的位置: ${state.position.inSeconds}秒');
      }
    } catch (e) {
      print('❌ [PlayerService] 恢复播放失败: $e');
    }
  }

  /// 更新均衡器增益（委托给 EqualizerService）
  Future<void> updateEqualizer(List<double> gains) async {
    await EqualizerService().updateEqualizer(gains);
    notifyListeners();
  }

  /// 开关均衡器（委托给 EqualizerService）
  Future<void> setEqualizerEnabled(bool enabled) async {
    await EqualizerService().setEqualizerEnabled(enabled);
    notifyListeners();
  }
}
