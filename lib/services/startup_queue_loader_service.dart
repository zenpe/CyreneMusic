import '../models/playlist.dart';
import 'app_settings_service.dart';
import 'auth_service.dart';
import 'player_service.dart';
import 'playlist_queue_service.dart';
import 'playlist_service.dart';

/// 启动播放队列加载服务
class StartupQueueLoaderService {
  static final StartupQueueLoaderService _instance =
      StartupQueueLoaderService._internal();
  factory StartupQueueLoaderService() => _instance;
  StartupQueueLoaderService._internal();

  bool _hasLoadedOnStartup = false;

  Future<void> loadStartupQueueIfNeeded() async {
    if (_hasLoadedOnStartup) return;
    _hasLoadedOnStartup = true;

    try {
      final settings = AppSettingsService();
      await settings.ensureInitialized();

      if (settings.startupQueueMode == StartupQueueMode.none) {
        print('ℹ️ [StartupQueueLoader] 启动队列模式为 none，跳过加载');
        return;
      }

      if (PlaylistQueueService().hasQueue) {
        print('ℹ️ [StartupQueueLoader] 已存在播放队列，跳过启动队列加载');
        return;
      }

      if (PlayerService().currentTrack != null) {
        print('ℹ️ [StartupQueueLoader] 已有正在播放曲目，跳过启动队列加载');
        return;
      }

      if (!AuthService().isLoggedIn) {
        print('ℹ️ [StartupQueueLoader] 未登录，跳过启动队列加载');
        return;
      }

      switch (settings.startupQueueMode) {
        case StartupQueueMode.none:
          break;
        case StartupQueueMode.favorites:
          await _loadFavoritesQueue();
          break;
        case StartupQueueMode.specificPlaylist:
          final playlistId = settings.startupQueuePlaylistId;
          if (playlistId == null) {
            print('⚠️ [StartupQueueLoader] 未设置指定歌单 ID，跳过');
            return;
          }
          await _loadPlaylistQueue(playlistId, QueueSource.playlist);
          break;
      }
    } catch (e) {
      print('❌ [StartupQueueLoader] 加载启动队列失败: $e');
    }
  }

  Future<void> _loadFavoritesQueue() async {
    final playlistService = PlaylistService();
    await playlistService.loadPlaylists();
    final favorite = playlistService.defaultPlaylist;
    if (favorite == null || favorite.id <= 0) {
      print('ℹ️ [StartupQueueLoader] 未找到可用收藏歌单');
      return;
    }
    await _loadTracksAndSetQueue(
      playlistService: playlistService,
      playlist: favorite,
      source: QueueSource.favorites,
    );
  }

  Future<void> _loadPlaylistQueue(int playlistId, QueueSource source) async {
    final playlistService = PlaylistService();
    await playlistService.loadPlaylists();
    final playlistIndex = playlistService.playlists.indexWhere(
      (item) => item.id == playlistId,
    );
    final playlist = playlistIndex == -1
        ? null
        : playlistService.playlists[playlistIndex];

    if (playlist == null) {
      print('⚠️ [StartupQueueLoader] 启动歌单不存在: $playlistId');
      await AppSettingsService().clearStartupQueuePlaylist();
      return;
    }

    await _loadTracksAndSetQueue(
      playlistService: playlistService,
      playlist: playlist,
      source: source,
    );
  }

  Future<void> _loadTracksAndSetQueue({
    required PlaylistService playlistService,
    required Playlist playlist,
    required QueueSource source,
  }) async {
    await playlistService.loadPlaylistTracks(playlist.id);
    final tracks = playlistService.currentTracks
        .map((item) => item.toTrack())
        .toList();
    if (tracks.isEmpty) {
      print('ℹ️ [StartupQueueLoader] 歌单为空，不创建启动队列: ${playlist.name}');
      return;
    }

    PlaylistQueueService().setQueue(tracks, 0, source);
    print(
      '✅ [StartupQueueLoader] 已加载启动队列: ${playlist.name} (${tracks.length} 首)',
    );
  }
}
