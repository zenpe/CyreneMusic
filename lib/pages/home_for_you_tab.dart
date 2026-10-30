import 'package:dio/dio.dart';
import '../utils/page_visibility_notifier.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/auth_service.dart';
import '../services/netease_login_service.dart';
import '../services/netease_recommend_service.dart';
import '../utils/theme_manager.dart';
import 'settings_page/netease_login_page.dart';
import 'home_page/personal_recommendation_cards.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import '../utils/netease_track.dart';
import 'home_page/mobile_playlist_grid.dart';
import 'home_page/daily_recommend_detail_page.dart';
import 'discover_playlist_detail_page.dart';
import '../services/netease_fm_service.dart';

/// Platform recommendations are scoped to the backend, Cyapi session and binding.
class HomeForYouTab extends StatefulWidget {
  const HomeForYouTab({
    super.key,
    this.onOpenPlaylistDetail,
    this.onOpenDailyDetail,
  });
  final void Function(int)? onOpenPlaylistDetail;
  final void Function(List<Map<String, dynamic>>)? onOpenDailyDetail;
  @override
  State<HomeForYouTab> createState() => _HomeForYouTabState();
}

class _HomeForYouTabState extends State<HomeForYouTab>
    with WidgetsBindingObserver {
  final accounts = NeteaseLoginService();
  Map<String, dynamic>? binding;
  List<Map<String, dynamic>> songs = [];
  List<Map<String, dynamic>> playlists = [];
  List<Map<String, dynamic>> fmSongs = [];
  final Map<String, String> errors = {};
  final Set<String> loading = {};
  String? accountError;
  int generation = 0;
  String? identity;
  bool checking = false;
  bool active = true;
  CancelToken? requestCancel;
  bool get visible => active && PageVisibilityNotifier().isHomePage;
  void _visibilityChanged() {
    if (visible) {
      unawaited(_reload());
    } else {
      generation++;
      requestCancel?.cancel('Page hidden');
    }
  }

  String get scope => '${accounts.scope}:${accounts.bindingRevision}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    accounts.addListener(_changed);
    PageVisibilityNotifier().addListener(_visibilityChanged);
    if (visible) unawaited(_reload());
  }

  void _changed() {
    if (!mounted || identity == scope) return;
    generation++;
    setState(() {
      songs = [];
      playlists = [];
      fmSongs = [];
      binding = null;
      errors.clear();
      loading.clear();
    });
    if (visible) unawaited(_reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    _visibilityChanged();
  }

  Future<void> _reload() async {
    if (!mounted || !visible) return;
    requestCancel?.cancel('Recommendations reloaded');
    requestCancel = CancelToken();
    final mine = ++generation;
    identity = scope;
    setState(() {
      checking = true;
      accountError = null;
    });
    try {
      final data = await accounts.fetchBindings();
      if (!mounted || mine != generation) return;
      binding = Map<String, dynamic>.from(
        (data['data'] as Map)['netease'] as Map,
      );
      identity = scope;
      setState(() => checking = false);
      if (binding?['bound'] != true) {
        setState(() {
          songs = [];
          playlists = [];
          fmSongs = [];
        });
        return;
      }
      await Future.wait([
        _load('songs', mine),
        _load('playlists', mine),
        _load('fm', mine),
      ]);
    } catch (e) {
      if (mounted && mine == generation) {
        setState(() {
          checking = false;
          accountError = e.toString();
        });
      }
    }
  }

  Future<void> _load(String section, int mine) async {
    setState(() {
      loading.add(section);
      errors.remove(section);
    });
    try {
      final service = NeteaseRecommendService();
      final result = section == 'songs'
          ? await service.fetchDailySongs(cancelToken: requestCancel)
          : section == 'fm'
          ? await service.fetchPersonalFm(cancelToken: requestCancel)
          : await service.fetchDailyPlaylists(cancelToken: requestCancel);
      if (!mounted || mine != generation || identity != scope) return;
      setState(() {
        if (section == 'songs') {
          songs = result;
        } else if (section == 'fm') {
          fmSongs = result;
        } else {
          playlists = result;
        }
      });
    } catch (e) {
      if (!mounted || mine != generation || identity != scope) return;
      if (e is NeteaseAccountException &&
          [
            'NETEASE_LOGIN_EXPIRED',
            'NETEASE_NOT_BOUND',
            'BINDING_CHANGED',
          ].contains(e.code)) {
        unawaited(_reload());
        return;
      }
      setState(() => errors[section] = e.toString());
    } finally {
      if (mounted && mine == generation) {
        setState(() => loading.remove(section));
      }
    }
  }

  Future<void> _playDaily(int index) async {
    final tracks = songs.map(neteaseSongToTrack).toList();
    if (index < 0 || index >= tracks.length) return;
    PlaylistQueueService().setQueue(tracks, index, QueueSource.playlist);
    await PlayerService().playTrack(tracks[index]);
  }

  Widget button(String text, VoidCallback? action) {
    if (ThemeManager().isDesktopFluentUI) {
      return fluent.Button(onPressed: action, child: Text(text));
    }
    if (ThemeManager().isCupertinoFramework) {
      return CupertinoButton(onPressed: action, child: Text(text));
    }
    return TextButton(onPressed: action, child: Text(text));
  }

  Future<void> _bind() async {
    final id = AuthService().currentUser?.id;
    if (id == null) return;
    await showNeteaseLogin(context, id);
    if (mounted) await _reload();
  }

  Widget section(String title, String key, Widget content, bool empty) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              button(
                '刷新',
                loading.contains(key)
                    ? null
                    : () => unawaited(_load(key, generation)),
              ),
            ],
          ),
          if (errors[key] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(errors[key]!),
            ),
          if (loading.contains(key) && empty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (empty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('网易云暂无推荐内容'),
            )
          else
            content,
          const SizedBox(height: 24),
        ],
      );
  @override
  Widget build(BuildContext context) {
    if (checking && binding == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (accountError != null) {
      return Column(
        children: [
          Text(accountError!),
          button('重试', () => unawaited(_reload())),
        ],
      );
    }
    if (binding?['bound'] != true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.music_note_rounded, size: 40),
            const SizedBox(height: 16),
            Text(binding?['status'] == 'expired' ? '网易云登录已过期' : '连接你的网易云音乐'),
            const SizedBox(height: 8),
            const Text('获取每日推荐、推荐歌单和私人 FM'),
            const SizedBox(height: 16),
            button(
              binding?['status'] == 'expired' ? '重新绑定' : '绑定网易云',
              () => unawaited(_bind()),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '来自 ${binding?['nickname'] ?? '网易云'} 的推荐',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        section(
          '每日推荐歌曲',
          'songs',
          DailySongsPreview(
            songs: songs,
            onPlay: (index) => unawaited(_playDaily(index)),
            onOpenAll: () {
              if (widget.onOpenDailyDetail != null) {
                widget.onOpenDailyDetail!(songs);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DailyRecommendDetailPage(tracks: songs),
                ),
              );
            },
          ),
          songs.isEmpty,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('私人 FM', style: Theme.of(context).textTheme.titleLarge),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([NeteaseFmService(), PlayerService()]),
          builder: (context, _) {
            final fm = NeteaseFmService();
            final player = PlayerService();
            final ownQueue =
                fm.active &&
                PlaylistQueueService().source == QueueSource.neteaseFm;
            final track = ownQueue ? player.currentTrack : null;
            return PersonalFmPreview(
              track:
                  track ??
                  (fmSongs.isEmpty ? null : neteaseSongToTrack(fmSongs.first)),
              playing: ownQueue && player.isPlaying,
              loading: fm.loading || loading.contains('fm'),
              error: fm.error ?? errors['fm'],
              onPlayPause: () {
                if (ownQueue) {
                  unawaited(player.togglePlayPause());
                } else {
                  unawaited(
                    fm.start(initialSongs: fmSongs.isEmpty ? null : fmSongs),
                  );
                }
              },
              onRefresh: () {
                if (ownQueue) {
                  unawaited(fm.start());
                } else {
                  unawaited(_load('fm', generation));
                }
              },
            );
          },
        ),
        const SizedBox(height: 24),
        section(
          '每日推荐歌单',
          'playlists',
          MobilePlaylistGrid(
            list: playlists,
            onTap: (id) {
              if (widget.onOpenPlaylistDetail != null) {
                widget.onOpenPlaylistDetail!(id);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiscoverPlaylistDetailPage(playlistId: id),
                ),
              );
            },
          ),
          playlists.isEmpty,
        ),
      ],
    );
  }

  @override
  void dispose() {
    generation++;
    requestCancel?.cancel('Page disposed');
    PageVisibilityNotifier().removeListener(_visibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    accounts.removeListener(_changed);
    super.dispose();
  }
}
