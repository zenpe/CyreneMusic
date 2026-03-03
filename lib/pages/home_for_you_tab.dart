import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/audio_source/audio_source_feature.dart';
import '../features/auth/auth_feature.dart';
import '../services/netease_recommend_service.dart';
import '../utils/theme_manager.dart';
import '../widgets/audio_source_prompt.dart';
import '../widgets/skeleton_loader.dart';
import 'home_page/bento_playlist_grid.dart';
import 'home_page/for_you_data.dart';
import 'home_page/greeting_header.dart';
import 'home_page/hero_section.dart';
import 'home_page/horizontal_playlist_carousel.dart';
import 'home_page/login_prompt.dart';
import 'home_page/mixed_playlist_grid.dart';
import 'home_page/mobile_daily_recommend_card.dart';
import 'home_page/mobile_newsong_list.dart';
import 'home_page/mobile_personal_fm.dart';
import 'home_page/mobile_playlist_grid.dart';
import 'home_page/newsong_cards.dart';
import 'settings_page/audio_source_settings.dart';

/// 首页 - 为你推荐 Tab 内容（SWR + 分区懒加载）
class HomeForYouTab extends StatefulWidget {
  const HomeForYouTab({super.key, this.onOpenPlaylistDetail, this.onOpenDailyDetail});

  final void Function(int playlistId)? onOpenPlaylistDetail;
  final void Function(List<Map<String, dynamic>> tracks)? onOpenDailyDetail;

  @override
  State<HomeForYouTab> createState() => _HomeForYouTabState();
}

class _HomeForYouTabState extends State<HomeForYouTab> {
  final AuthFacade _authFacade = AuthFacade();
  final AudioSourceFacade _audioSourceFacade = AudioSourceFacade();

  late bool _lastAudioConfigured;
  int _loadVersion = 0;

  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  String? _loadError;

  List<Map<String, dynamic>> _dailySongs = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _fm = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dailyPlaylists = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _personalizedPlaylists = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _radarPlaylists = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _personalizedNewsongs = <Map<String, dynamic>>[];

  bool _dailySongsLoading = false;
  bool _fmLoading = false;
  bool _dailyPlaylistsLoading = false;
  bool _personalizedPlaylistsLoading = false;
  bool _radarPlaylistsLoading = false;
  bool _personalizedNewsongsLoading = false;

  bool get _hasData =>
      _dailySongs.isNotEmpty ||
      _fm.isNotEmpty ||
      _dailyPlaylists.isNotEmpty ||
      _personalizedPlaylists.isNotEmpty ||
      _radarPlaylists.isNotEmpty ||
      _personalizedNewsongs.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _lastAudioConfigured = _audioSourceFacade.isAudioConfigured;
    _audioSourceFacade.addAudioSourceStateListener(_onAudioSourceChanged);
    _reloadData(forceNetwork: false);
  }

  @override
  void dispose() {
    _loadVersion++;
    _audioSourceFacade.removeAudioSourceStateListener(_onAudioSourceChanged);
    super.dispose();
  }

  void _onAudioSourceChanged() {
    final isConfigured = _audioSourceFacade.isAudioConfigured;
    if (!mounted || isConfigured == _lastAudioConfigured) {
      return;
    }
    _lastAudioConfigured = isConfigured;
    if (isConfigured) {
      _reloadData(forceNetwork: false);
      return;
    }
    setState(() {});
  }

  Future<void> _reloadData({required bool forceNetwork}) async {
    final loadId = ++_loadVersion;
    final cached = await _readCacheState();
    if (!_isLoadActive(loadId)) {
      return;
    }

    if (cached != null) {
      setState(() {
        _applyForYouData(cached.data);
        _isInitialLoading = false;
        _loadError = null;
      });
    }

    final shouldFetchNetwork = forceNetwork || cached == null || !cached.isFresh;
    if (!shouldFetchNetwork) {
      setState(() {
        _isRefreshing = false;
      });
      return;
    }

    setState(() {
      _isRefreshing = true;
      _loadError = null;
      if (!_hasData) {
        _isInitialLoading = true;
        _setAllSectionLoading(true);
      } else {
        _setAllSectionLoading(false);
      }
    });

    await _loadSections(loadId);
  }

  Future<void> _loadSections(int loadId) async {
    final service = NeteaseRecommendService();
    final sectionErrors = <String>[];

    await Future.wait<void>([
      _loadSection(
        loadId: loadId,
        sectionName: '每日推荐',
        request: service.fetchDailySongs,
        sectionErrors: sectionErrors,
        assign: (items) => _dailySongs = items,
        setLoading: (value) => _dailySongsLoading = value,
      ),
      _loadSection(
        loadId: loadId,
        sectionName: '私人FM',
        request: service.fetchPersonalFm,
        sectionErrors: sectionErrors,
        assign: (items) => _fm = items,
        setLoading: (value) => _fmLoading = value,
      ),
      _loadSection(
        loadId: loadId,
        sectionName: '每日推荐歌单',
        request: service.fetchDailyPlaylists,
        sectionErrors: sectionErrors,
        assign: (items) => _dailyPlaylists = items,
        setLoading: (value) => _dailyPlaylistsLoading = value,
      ),
      _loadSection(
        loadId: loadId,
        sectionName: '专属歌单',
        request: () => service.fetchPersonalizedPlaylists(limit: 12),
        sectionErrors: sectionErrors,
        assign: (items) => _personalizedPlaylists = items,
        setLoading: (value) => _personalizedPlaylistsLoading = value,
      ),
      _loadSection(
        loadId: loadId,
        sectionName: '雷达歌单',
        request: service.fetchRadarPlaylists,
        sectionErrors: sectionErrors,
        assign: (items) => _radarPlaylists = items,
        setLoading: (value) => _radarPlaylistsLoading = value,
      ),
      _loadSection(
        loadId: loadId,
        sectionName: '新歌',
        request: () => service.fetchPersonalizedNewsongs(limit: 10),
        sectionErrors: sectionErrors,
        assign: (items) => _personalizedNewsongs = items,
        setLoading: (value) => _personalizedNewsongsLoading = value,
      ),
    ]);

    if (!_isLoadActive(loadId)) {
      return;
    }

    await _saveCurrentDataToCache();
    if (!_isLoadActive(loadId)) {
      return;
    }

    setState(() {
      _isRefreshing = false;
      _isInitialLoading = !_hasData;
      _setAllSectionLoading(false);
      if (_hasData) {
        _loadError = null;
      } else if (sectionErrors.isNotEmpty) {
        _loadError = '加载失败：${sectionErrors.join('、')}';
      } else {
        _loadError = '加载失败';
      }
    });
  }

  Future<void> _loadSection({
    required int loadId,
    required String sectionName,
    required Future<List<Map<String, dynamic>>> Function() request,
    required List<String> sectionErrors,
    required void Function(List<Map<String, dynamic>> items) assign,
    required void Function(bool value) setLoading,
  }) async {
    try {
      final result = await request();
      if (!_isLoadActive(loadId)) {
        return;
      }
      setState(() {
        assign(result);
        setLoading(false);
      });
    } catch (_) {
      if (!_isLoadActive(loadId)) {
        return;
      }
      sectionErrors.add(sectionName);
      setState(() {
        setLoading(false);
      });
    }
  }

  bool _isLoadActive(int loadId) {
    return mounted && loadId == _loadVersion;
  }

  void _setAllSectionLoading(bool value) {
    _dailySongsLoading = value;
    _fmLoading = value;
    _dailyPlaylistsLoading = value;
    _personalizedPlaylistsLoading = value;
    _radarPlaylistsLoading = value;
    _personalizedNewsongsLoading = value;
  }

  void _applyForYouData(ForYouData data) {
    _dailySongs = List<Map<String, dynamic>>.from(data.dailySongs);
    _fm = List<Map<String, dynamic>>.from(data.fm);
    _dailyPlaylists = List<Map<String, dynamic>>.from(data.dailyPlaylists);
    _personalizedPlaylists = List<Map<String, dynamic>>.from(data.personalizedPlaylists);
    _radarPlaylists = List<Map<String, dynamic>>.from(data.radarPlaylists);
    _personalizedNewsongs = List<Map<String, dynamic>>.from(data.personalizedNewsongs);
  }

  Future<_CachedForYouState?> _readCacheState() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheBase = _cacheBaseKey();
    final dataKey = '${cacheBase}_data';
    final expireKey = '${cacheBase}_expire';

    final jsonString = prefs.getString(dataKey);
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    try {
      final data = ForYouData.fromJsonString(jsonString);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final expireMs = prefs.getInt(expireKey);
      final isFresh = expireMs != null && nowMs < expireMs;
      return _CachedForYouState(data: data, isFresh: isFresh);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCurrentDataToCache() async {
    if (!_hasData) {
      return;
    }

    final now = DateTime.now();
    final result = ForYouData(
      dailySongs: _dailySongs,
      fm: _fm,
      dailyPlaylists: _dailyPlaylists,
      personalizedPlaylists: _personalizedPlaylists,
      radarPlaylists: _radarPlaylists,
      personalizedNewsongs: _personalizedNewsongs,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheBase = _cacheBaseKey();
      final dataKey = '${cacheBase}_data';
      final expireKey = '${cacheBase}_expire';
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      await prefs.setString(dataKey, result.toJsonString());
      await prefs.setInt(expireKey, endOfDay.millisecondsSinceEpoch);
    } catch (_) {}
  }

  String _cacheBaseKey() {
    final userId = _authFacade.currentUser?.id?.toString() ?? 'guest';
    return 'home_for_you_$userId';
  }

  /// 导航到音源设置页面
  void _navigateToAudioSourceSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AudioSourceSettings(),
      ),
    );
  }

  Widget _buildRefreshingIndicator({required bool isCupertino}) {
    if (!_isRefreshing) {
      return const SizedBox.shrink();
    }
    if (isCupertino) {
      return const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 4),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }

  Widget _buildSectionSkeleton({required double height}) {
    return SkeletonLoader(
      width: double.infinity,
      height: height,
      borderRadius: BorderRadius.circular(16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino =
        (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isMobile = Platform.isIOS || Platform.isAndroid;

    // 未登录状态下显示登录提示
    if (!_authFacade.isLoggedIn) {
      return ForYouLoginPrompt(
        onLoginPressed: () {
          if (mounted && _authFacade.isLoggedIn) {
            _reloadData(forceNetwork: false);
          }
        },
      );
    }

    // 已登录但音源未配置时，显示音源配置提示
    if (!_audioSourceFacade.isAudioConfigured) {
      return AudioSourcePrompt(
        onConfigurePressed: () {
          _navigateToAudioSourceSettings(context);
        },
      );
    }

    if (_isInitialLoading && !_hasData) {
      if (isMobile) {
        return const MobileForYouSkeleton();
      }
      return const ForYouSkeleton();
    }

    if (_loadError != null && !_hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text('加载失败：$_loadError'),
        ),
      );
    }

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRefreshingIndicator(isCupertino: isCupertino),
          const GreetingHeader(),
          if (_dailySongsLoading && _dailySongs.isEmpty)
            _buildSectionSkeleton(height: 180)
          else
            MobileDailyRecommendCard(
              tracks: _dailySongs,
              onOpenDetail: () => widget.onOpenDailyDetail?.call(_dailySongs),
            ),
          SizedBox(height: isCupertino ? 24 : 32),
          SectionTitle(title: '私人FM'),
          if (_fmLoading && _fm.isEmpty)
            _buildSectionSkeleton(height: 148)
          else
            MobilePersonalFm(list: _fm),
          SizedBox(height: isCupertino ? 24 : 32),
          SectionTitle(title: '每日推荐歌单'),
          if (_dailyPlaylistsLoading && _dailyPlaylists.isEmpty)
            _buildSectionSkeleton(height: 280)
          else
            MobilePlaylistGrid(
              list: _dailyPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
          SizedBox(height: isCupertino ? 24 : 32),
          SectionTitle(title: '专属歌单'),
          if (_personalizedPlaylistsLoading && _personalizedPlaylists.isEmpty)
            _buildSectionSkeleton(height: 280)
          else
            MobilePlaylistGrid(
              list: _personalizedPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
          SizedBox(height: isCupertino ? 24 : 32),
          SectionTitle(title: '雷达歌单'),
          if (_radarPlaylistsLoading && _radarPlaylists.isEmpty)
            _buildSectionSkeleton(height: 280)
          else
            MobilePlaylistGrid(
              list: _radarPlaylists,
              onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
            ),
          SizedBox(height: isCupertino ? 24 : 32),
          SectionTitle(title: '个性化新歌'),
          if (_personalizedNewsongsLoading && _personalizedNewsongs.isEmpty)
            _buildSectionSkeleton(height: 220)
          else
            MobileNewsongList(list: _personalizedNewsongs),
          const SizedBox(height: 16),
        ],
      );
    }

    final heroLoading =
        (_dailySongsLoading && _dailySongs.isEmpty) || (_fmLoading && _fm.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRefreshingIndicator(isCupertino: false),
        const GreetingHeader(),
        const SizedBox(height: 16),
        if (heroLoading)
          _buildSectionSkeleton(height: 220)
        else
          HeroSection(
            dailySongs: _dailySongs,
            fmList: _fm,
            onOpenDailyDetail: () => widget.onOpenDailyDetail?.call(_dailySongs),
          ),
        const SizedBox(height: 28),
        SectionTitle(title: '每日推荐歌单'),
        if (_dailyPlaylistsLoading && _dailyPlaylists.isEmpty)
          _buildSectionSkeleton(height: 320)
        else
          BentoPlaylistGrid(
            list: _dailyPlaylists,
            onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
          ),
        const SizedBox(height: 28),
        SectionTitle(title: '专属歌单'),
        if (_personalizedPlaylistsLoading && _personalizedPlaylists.isEmpty)
          _buildSectionSkeleton(height: 220)
        else
          HorizontalPlaylistCarousel(
            list: _personalizedPlaylists,
            onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
          ),
        const SizedBox(height: 28),
        SectionTitle(title: '雷达歌单'),
        if (_radarPlaylistsLoading && _radarPlaylists.isEmpty)
          _buildSectionSkeleton(height: 320)
        else
          MixedSizePlaylistGrid(
            list: _radarPlaylists,
            onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
          ),
        const SizedBox(height: 28),
        SectionTitle(title: '发现新歌'),
        if (_personalizedNewsongsLoading && _personalizedNewsongs.isEmpty)
          _buildSectionSkeleton(height: 280)
        else
          NewsongCards(list: _personalizedNewsongs),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CachedForYouState {
  final ForYouData data;
  final bool isFresh;

  const _CachedForYouState({
    required this.data,
    required this.isFresh,
  });
}
