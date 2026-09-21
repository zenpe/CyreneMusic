import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../features/auth/auth_feature.dart';
import '../utils/theme_manager.dart';
import '../services/url_service.dart';
import '../services/location_service.dart';
import '../services/layout_preference_service.dart';
import '../services/cache_service.dart';
import '../services/download_service.dart';
import '../services/audio_quality_service.dart';
import '../services/player_background_service.dart';
import '../services/player_service.dart';
import '../services/audio_source_service.dart';
import '../services/developer_mode_service.dart';
import '../services/version_service.dart';
import '../services/global_back_handler_service.dart';
import '../models/song_detail.dart';
import 'settings_page/user_card.dart';
import 'settings_page/third_party_accounts.dart';
import 'settings_page/appearance_settings.dart';
import 'settings_page/lyric_settings.dart';
import 'settings_page/playback_settings.dart';
import 'settings_page/search_settings.dart';
import 'settings_page/network_settings.dart';
import 'settings_page/storage_settings.dart';
import 'settings_page/about_settings.dart';
import 'settings_page/other_settings.dart';
import 'settings_page/appearance_settings_page.dart';
import 'settings_page/third_party_accounts_page.dart';
import 'settings_page/lyric_settings_page.dart';
import 'settings_page/audio_source_settings_page.dart';
import 'settings_page/about_settings_page.dart';
import 'settings_page/other_settings_page.dart';
import 'settings_page/lab_functions.dart';
import 'settings_page/lab_functions_page.dart';

enum SettingsSubPage {
  none,
  appearance,
  thirdPartyAccounts,
  lyric,
  audioSource,
  about,
  labFunctions,
  other,
}

/// 设置页面
class SettingsPage extends StatefulWidget {
  final SettingsSubPage initialSubPage;
  final bool isActive;

  const SettingsPage({
    super.key,
    this.initialSubPage = SettingsSubPage.none,
    this.isActive = true,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthFacade _authFacade = AuthFacade();
  bool _rebuildScheduled = false;
  
  // 当前显示的子页面
  SettingsSubPage _currentSubPage = SettingsSubPage.none;
  bool _autoOpenDone = false;

  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rebuildScheduled = false;
      setState(() {});
    });
  }

  void _maybeAutoOpenSubPage() {
    if (_autoOpenDone) return;
    if (widget.initialSubPage == SettingsSubPage.none) return;
    if (!widget.isActive) return;
    _autoOpenDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openSubPage(widget.initialSubPage);
    });
  }

  @override
  void initState() {
    super.initState();
    print('⚙️ [SettingsPage] 初始化设置页面...');
    
    // 监听主题变化
    ThemeManager().addListener(_onThemeChanged);
    // 监听 URL 服务变化
    UrlService().addListener(_onUrlServiceChanged);
    // 监听认证状态变化
    _authFacade.addAuthStateListener(_onAuthChanged);
    // 监听位置信息变化
    LocationService().addListener(_onLocationChanged);
    // 监听布局偏好变化
    LayoutPreferenceService().addListener(_onLayoutPreferenceChanged);
    // 监听缓存服务变化
    CacheService().addListener(_onCacheChanged);
    // 监听下载服务变化
    DownloadService().addListener(_onDownloadChanged);
    // 监听音质服务变化
    AudioQualityService().addListener(_onAudioQualityChanged);
    // 监听播放器背景服务变化
    PlayerBackgroundService().addListener(_onPlayerBackgroundChanged);
    
    // 如果已登录，获取 IP 归属地
    final isLoggedIn = _authFacade.isLoggedIn;
    print('⚙️ [SettingsPage] 当前登录状态: $isLoggedIn');
    
    if (isLoggedIn) {
      print('⚙️ [SettingsPage] 用户已登录，开始获取IP归属地...');
      LocationService().fetchLocation();
    } else {
      print('⚙️ [SettingsPage] 用户未登录，跳过获取IP归属地');
    }

    _maybeAutoOpenSubPage();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive) {
      _autoOpenDone = false;
      return;
    }
    _maybeAutoOpenSubPage();
  }


  @override
  void dispose() {
    ThemeManager().removeListener(_onThemeChanged);
    UrlService().removeListener(_onUrlServiceChanged);
    _authFacade.removeAuthStateListener(_onAuthChanged);
    LocationService().removeListener(_onLocationChanged);
    LayoutPreferenceService().removeListener(_onLayoutPreferenceChanged);
    CacheService().removeListener(_onCacheChanged);
    DownloadService().removeListener(_onDownloadChanged);
    AudioQualityService().removeListener(_onAudioQualityChanged);
    PlayerBackgroundService().removeListener(_onPlayerBackgroundChanged);
    // 注销返回处理器
    GlobalBackHandlerService().unregister('settings_sub_page');
    super.dispose();
  }

  void _onThemeChanged() {
    _scheduleRebuild();
  }

  void _onUrlServiceChanged() {
    _scheduleRebuild();
  }

  void _onAuthChanged() {
    // 登录状态变化时获取/清除位置信息
    if (_authFacade.isLoggedIn) {
      print('👤 [SettingsPage] 用户已登录，开始获取IP归属地...');
      LocationService().fetchLocation();
    } else {
      print('👤 [SettingsPage] 用户已退出，清除IP归属地...');
      LocationService().clearLocation();
    }
    _scheduleRebuild();
  }

  void _onLocationChanged() {
    print('🌍 [SettingsPage] 位置信息已更新，刷新UI...');
    _scheduleRebuild();
  }

  void _onLayoutPreferenceChanged() {
    _scheduleRebuild();
  }

  void _onCacheChanged() {
    _scheduleRebuild();
  }

  void _onDownloadChanged() {
    _scheduleRebuild();
  }

  void _onAudioQualityChanged() {
    _scheduleRebuild();
  }

  void _onPlayerBackgroundChanged() {
    _scheduleRebuild();
  }


  /// 打开子页面
  void openSubPage(SettingsSubPage subPage) {
    final isCupertinoUI = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
    
    if (isCupertinoUI) {
      // iOS 使用原生 Navigator 动画
      _openCupertinoSubPage(context, subPage);
    } else {
      // 其他平台使用内嵌动画
      setState(() {
        _currentSubPage = subPage;
      });
      // 注册返回处理器
      GlobalBackHandlerService().register('settings_sub_page', () {
        if (_currentSubPage != SettingsSubPage.none) {
          closeSubPage();
          return true;
        }
        return false;
      });
    }
  }

  /// 使用原生 iOS 导航打开子页面
  void _openCupertinoSubPage(BuildContext context, SettingsSubPage subPage) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => _buildCupertinoSubPageWidget(subPage),
      ),
    );
  }

  /// 构建 Cupertino 子页面 Widget（带完整导航栏）
  Widget _buildCupertinoSubPageWidget(SettingsSubPage subPage) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground;
    
    Widget content;
    String title;
    
    switch (subPage) {
      case SettingsSubPage.appearance:
        content = AppearanceSettingsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '外观';
      case SettingsSubPage.thirdPartyAccounts:
        content = ThirdPartyAccountsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '第三方账号';
      case SettingsSubPage.lyric:
        content = LyricSettingsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '歌词';
      case SettingsSubPage.audioSource:
        content = AudioSourceSettingsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '音源设置';
      case SettingsSubPage.about:
        content = AboutSettingsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '关于';
      case SettingsSubPage.labFunctions:
        content = LabFunctionsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '实验室功能';
      case SettingsSubPage.other:
        content = OtherSettingsContent(onBack: () => Navigator.pop(context), embed: true);
        title = '其它设置';
      case SettingsSubPage.none:
        return const SizedBox.shrink();
    }
    
    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: backgroundColor,
        border: null,
      ),
      child: SafeArea(
        // 使用 Material 包裹以提供正确的 DefaultTextStyle，修复黄色下划线问题
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: TextStyle(
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              fontSize: 17,
              decoration: TextDecoration.none,
              fontFamily: '.SF Pro Text',
            ),
            child: content,
          ),
        ),
      ),
    );
  }
  
  /// 关闭子页面，返回主设置页面
  void closeSubPage() {
    setState(() {
      _currentSubPage = SettingsSubPage.none;
    });
    // 注销返回处理器
    GlobalBackHandlerService().unregister('settings_sub_page');
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否使用 Fluent UI
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    final isCupertinoUI = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    if (isCupertinoUI) {
      return _buildCupertinoUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// 构建 Material UI 版本 (Inset Grouped 现代分组风格)
  Widget _buildMaterialUI(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final accent = themeColor ?? colorScheme.primary;
        final bgBase = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF7F8FA);

        return Scaffold(
          backgroundColor: bgBase,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: _currentSubPage != SettingsSubPage.none
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: closeSubPage,
                  )
                : null,
            title: Text(
              _getPageTitle(),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: Stack(
            children: [
              // 顶部动态微光光晕 (与全站流体氛围统一)
              if (_currentSubPage == SettingsSubPage.none)
                Positioned(
                  top: -80,
                  left: 0,
                  right: 0,
                  height: 300,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.0, -0.6),
                          radius: 1.25,
                          colors: [
                            accent.withOpacity(isDark ? 0.20 : 0.14),
                            accent.withOpacity(isDark ? 0.07 : 0.04),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final offset = child.key == const ValueKey('main_settings')
                      ? const Offset(-1.0, 0.0)
                      : const Offset(1.0, 0.0);
                      
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: offset,
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOutCubic,
                    )),
                    child: child,
                  );
                },
                child: _currentSubPage != SettingsSubPage.none
                    ? KeyedSubtree(
                        key: ValueKey('sub_settings_${_currentSubPage.name}'),
                        child: _buildMaterialSubPage(context, colorScheme),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('main_settings'),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          children: [
                            // 用户卡片（需随登录状态刷新）
                            const UserCard(),
                            const SizedBox(height: 16),

                            // 分组 1：账号与实验
                            _buildMaterialSettingsGroup(
                              context,
                              header: '账号与功能',
                              children: [
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.link_rounded,
                                  iconColor: const Color(0xFF5856D6),
                                  title: '第三方账号管理',
                                  subtitle: '网易云音乐、酷狗等绑定',
                                  onTap: () => openSubPage(SettingsSubPage.thirdPartyAccounts),
                                ),
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.science_outlined,
                                  iconColor: const Color(0xFF9C27B0),
                                  title: '实验室功能',
                                  subtitle: '抢先体验各种实验性新特性',
                                  onTap: () => openSubPage(SettingsSubPage.labFunctions),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 分组 2：个性化与显示
                            _buildMaterialSettingsGroup(
                              context,
                              header: '个性化与显示',
                              children: [
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.palette_outlined,
                                  iconColor: const Color(0xFFFF9500),
                                  title: '外观设置',
                                  subtitle: '主题模式、主题色、界面风格',
                                  onTap: () => openSubPage(SettingsSubPage.appearance),
                                ),
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.lyrics_outlined,
                                  iconColor: const Color(0xFF34C759),
                                  title: '悬浮歌词',
                                  subtitle: '桌面悬浮歌词与显示偏好',
                                  onTap: () => openSubPage(SettingsSubPage.lyric),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 分组 3：播放与音源
                            _buildMaterialSettingsGroup(
                              context,
                              header: '播放与音源',
                              children: [
                                ListenableBuilder(
                                  listenable: AudioQualityService(),
                                  builder: (context, _) => _buildMaterialSettingsItem(
                                    context,
                                    icon: Icons.high_quality_outlined,
                                    iconColor: const Color(0xFF007AFF),
                                    title: '音质选择',
                                    subtitle: '${AudioQualityService().getQualityName()} - ${AudioQualityService().getQualityDescription()}',
                                    onTap: () => _showAudioQualityDialogMaterial(context),
                                  ),
                                ),
                                ListenableBuilder(
                                  listenable: DeveloperModeService(),
                                  builder: (context, _) => _buildMaterialSettingsItem(
                                    context,
                                    icon: Icons.merge_type_rounded,
                                    iconColor: const Color(0xFF00BCD4),
                                    title: '合并搜索结果',
                                    subtitle: DeveloperModeService().isSearchResultMergeEnabled
                                        ? '开启：聚合多平台相同歌曲'
                                        : '关闭：分平台独立展示',
                                    trailing: Switch(
                                      value: DeveloperModeService().isSearchResultMergeEnabled,
                                      onChanged: (v) => DeveloperModeService().toggleSearchResultMerge(v),
                                    ),
                                    onTap: () => DeveloperModeService().toggleSearchResultMerge(
                                      !DeveloperModeService().isSearchResultMergeEnabled,
                                    ),
                                  ),
                                ),
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.cloud_outlined,
                                  iconColor: const Color(0xFF3F51B5),
                                  title: '音源设置',
                                  subtitle: '音源服务配置与网络连接',
                                  onTap: () => openSubPage(SettingsSubPage.audioSource),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 分组 4：存储与缓存
                            _buildMaterialSettingsGroup(
                              context,
                              header: '存储空间',
                              children: [
                                const StorageSettings(),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 分组 5：系统与其它
                            _buildMaterialSettingsGroup(
                              context,
                              header: '系统与其它',
                              children: [
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.tune_rounded,
                                  iconColor: const Color(0xFF607D8B),
                                  title: '其它设置',
                                  subtitle: '启动提示、更新提示等选项',
                                  onTap: () => openSubPage(SettingsSubPage.other),
                                ),
                                _buildMaterialSettingsItem(
                                  context,
                                  icon: Icons.info_outline_rounded,
                                  iconColor: const Color(0xFF795548),
                                  title: '关于',
                                  subtitle: '版本 ${VersionService().currentVersion} • 开源致谢',
                                  onTap: () => openSubPage(SettingsSubPage.about),
                                ),
                              ],
                            ),

                            const SizedBox(height: 120), // 彻底避让悬浮 MiniPlayer
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建 Material Inset Grouped 分组容器
  Widget _buildMaterialSettingsGroup(
    BuildContext context, {
    String? header,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4, bottom: 8),
            child: Text(
              header,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                letterSpacing: 0.1,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: _buildMaterialChildrenWithDividers(context, children, isDark),
          ),
        ),
      ],
    );
  }

  /// 构建带浅分隔线的 Material 列表
  List<Widget> _buildMaterialChildrenWithDividers(
    BuildContext context,
    List<Widget> children,
    bool isDark,
  ) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
            ),
          ),
        );
      }
    }
    return result;
  }

  /// 构建统一现代样式的 Material 设置项
  Widget _buildMaterialSettingsItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }

  /// 显示音质选择弹窗 (Material)
  void _showAudioQualityDialogMaterial(BuildContext context) {
    final qualityService = AudioQualityService();
    final currentQuality = qualityService.currentQuality;
    final sourceType = AudioSourceService().sourceType;
    final supportedQualities = qualityService.getSupportedQualities(sourceType);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择音质'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: supportedQualities.map((quality) => RadioListTile<AudioQuality>(
            title: Text(qualityService.getQualityName(quality)),
            subtitle: Text(qualityService.getQualityDescription(quality)),
            value: quality,
            groupValue: currentQuality,
            onChanged: (value) {
              if (value != null) {
                qualityService.setQuality(value);
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('音质设置已更新'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              }
            },
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  String _getPageTitle() {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return '外观设置';
      case SettingsSubPage.thirdPartyAccounts:
        return '第三方账号管理';
      case SettingsSubPage.lyric:
        return '歌词设置';
      case SettingsSubPage.audioSource:
        return '音源设置';
      case SettingsSubPage.about:
        return '关于';
      case SettingsSubPage.labFunctions:
        return '实验室功能';
      case SettingsSubPage.other:
        return '其它设置';
      case SettingsSubPage.none:
        return '设置';
    }
  }

  Widget _buildMaterialSubPage(BuildContext context, ColorScheme colorScheme) {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return AppearanceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.thirdPartyAccounts:
        return ThirdPartyAccountsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.lyric:
        return LyricSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.audioSource:
        return AudioSourceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.about:
        return AboutSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.labFunctions:
        return LabFunctionsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.other:
        return OtherSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.none:
        return const SizedBox.shrink();
    }
  }

  /// 构建 Cupertino UI 版本（iOS 26 风格）
  /// 注意：子页面现在通过 Navigator.push + CupertinoPageRoute 实现原生动画
  Widget _buildCupertinoUI(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground;
    
    // 主设置页面使用大标题导航栏 (iOS 26 风格)
    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      child: _buildCupertinoMainContent(context, isDark, backgroundColor),
    );
  }

  /// 构建 Cupertino 主设置页面内容
  Widget _buildCupertinoMainContent(BuildContext context, bool isDark, Color backgroundColor) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // iOS 26 大标题导航栏
        CupertinoSliverNavigationBar(
          largeTitle: const Text('设置'),
          backgroundColor: backgroundColor,
          border: null,
          stretch: false,
        ),
        
        // 主内容
        SliverToBoxAdapter(
          child: SafeArea(
            top: false,
            child: Column(
              children: [
              const SizedBox(height: 8),
              
              // 用户卡片 - iOS 26 风格
              _buildCupertinoUserSection(context, isDark),
              
              const SizedBox(height: 24),

              
              // 账号设置分组
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '账号',
                children: [
                  _buildCupertinoSettingsItem(
                    context,
                    isDark: isDark,
                    icon: CupertinoIcons.link,
                    iconColor: const Color(0xFF5856D6),
                    title: '第三方账号',
                    subtitle: '网易云音乐等',
                    onTap: () => openSubPage(SettingsSubPage.thirdPartyAccounts),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 外观与显示分组
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '外观与显示',
                children: [
                  _buildCupertinoSettingsItem(
                    context,
                    isDark: isDark,
                    icon: CupertinoIcons.paintbrush,
                    iconColor: const Color(0xFFFF9500),
                    title: '外观',
                    subtitle: '主题、颜色、界面',
                    onTap: () => openSubPage(SettingsSubPage.appearance),
                  ),
                  _buildCupertinoSettingsItem(
                    context,
                    isDark: isDark,
                    icon: CupertinoIcons.text_quote,
                    iconColor: const Color(0xFF34C759),
                    title: '歌词',
                    subtitle: '歌词显示设置',
                    onTap: () => openSubPage(SettingsSubPage.lyric),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 播放设置分组
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '播放',
                children: [
                  const SearchSettings(),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 网络设置分组
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '网络',
                children: [
                  NetworkSettings(onAudioSourceTap: () => openSubPage(SettingsSubPage.audioSource)),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 存储设置分组
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '存储',
                children: const [
                  StorageSettings(),
                ],
              ),
              
              const SizedBox(height: 24),

              // 其它设置分组
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '其它',
                children: [
                  _buildCupertinoSettingsItem(
                    context,
                    isDark: isDark,
                    icon: CupertinoIcons.ellipsis,
                    iconColor: CupertinoColors.systemGrey,
                    title: '其它设置',
                    subtitle: '启动提示、更新提示',
                    onTap: () => openSubPage(SettingsSubPage.other),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              
              _buildCupertinoSettingsGroup(
                context,
                isDark: isDark,
                header: '关于',
                children: [
                  AboutSettings(onTap: () => openSubPage(SettingsSubPage.about)),
                ],
              ),
              
              const SizedBox(height: 100), // 底部留白
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  /// 构建 iOS 26 风格的用户卡片区域
  Widget _buildCupertinoUserSection(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: UserCard(),
      ),
    );
  }
  
  /// 构建 iOS 26 风格的设置分组
  Widget _buildCupertinoSettingsGroup(
    BuildContext context, {
    required bool isDark,
    String? header,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 8),
            child: Text(
              header.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.systemGrey,
                letterSpacing: -0.08,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: _buildChildrenWithDividers(context, children, isDark),
          ),
        ),
      ],
    );
  }
  
  /// 构建带分隔线的子项列表
  List<Widget> _buildChildrenWithDividers(BuildContext context, List<Widget> children, bool isDark) {
    final List<Widget> result = [];
    
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Container(
              height: 0.5,
              color: isDark 
                  ? CupertinoColors.systemGrey.withOpacity(0.3) 
                  : CupertinoColors.systemGrey.withOpacity(0.3),
            ),
          ),
        );
      }
    }
    
    return result;
  }
  
  /// 构建 iOS 26 风格的设置项
  Widget _buildCupertinoSettingsItem(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // iOS 风格图标容器
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: CupertinoColors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: CupertinoColors.systemGrey.withOpacity(0.6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCupertinoSubPage(BuildContext context) {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return AppearanceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.thirdPartyAccounts:
        return ThirdPartyAccountsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.lyric:
        return LyricSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.audioSource:
        return AudioSourceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.about:
        return AboutSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.labFunctions:
        return LabFunctionsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.other:
        return OtherSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.none:
        return const SizedBox.shrink();
    }
  }

  /// 构建 Fluent UI 版本（Windows 11 风格）
  Widget _buildFluentUI(BuildContext context) {
    return fluent_ui.ScaffoldPage(
      header: fluent_ui.PageHeader(
        title: _currentSubPage == SettingsSubPage.none
            ? const Text('设置')
            : _buildFluentHeader(context),
      ),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          // 简单的左右滑动效果
          final isMain = child.key == const ValueKey('main_settings');
          final isSub = child.key is ValueKey<String> && (child.key as ValueKey<String>).value.startsWith('sub_settings_');
          
          final offset = isMain
              ? const Offset(-0.2, 0.0) // 主页面移出时略微向左
              : (isSub ? const Offset(0.2, 0.0) : const Offset(1.0, 0.0)); // 子页面进入时从右侧拉入
              
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: offset,
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              )),
              child: child,
            ),
          );
        },
        child: _currentSubPage != SettingsSubPage.none
            ? KeyedSubtree(
                key: ValueKey('sub_settings_${_currentSubPage.name}'),
                child: _buildFluentSubPage(context),
              )
            : KeyedSubtree(
                key: const ValueKey('main_settings'),
                child: _buildFluentMainContent(context),
              ),
      ),
    );
  }

  /// 构建 Fluent UI 主内容列表
  Widget _buildFluentMainContent(BuildContext context) {
    return fluent_ui.ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0),
      children: [
        // 用户卡片
        UserCard(),
        const SizedBox(height: 16),

        // 实验室功能
        LabFunctions(onTap: () => openSubPage(SettingsSubPage.labFunctions)),
        const SizedBox(height: 16),
        
        // 分组设置
        ThirdPartyAccounts(onTap: () => openSubPage(SettingsSubPage.thirdPartyAccounts)),
        const SizedBox(height: 16),
        
        AppearanceSettings(onTap: () => openSubPage(SettingsSubPage.appearance)),
        const SizedBox(height: 16),
        
        LyricSettings(onTap: () => openSubPage(SettingsSubPage.lyric)),
        const SizedBox(height: 16),
        
        const PlaybackSettings(),
        const SizedBox(height: 16),
        
        const SearchSettings(),
        const SizedBox(height: 16),
        
        NetworkSettings(onAudioSourceTap: () => openSubPage(SettingsSubPage.audioSource)),
        const SizedBox(height: 16),
        
        const StorageSettings(),
        const SizedBox(height: 16),

        OtherSettings(onTap: () => openSubPage(SettingsSubPage.other)),
        const SizedBox(height: 16),
        
        AboutSettings(onTap: () => openSubPage(SettingsSubPage.about)),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildFluentSubPage(BuildContext context) {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return AppearanceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.thirdPartyAccounts:
        return ThirdPartyAccountsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.lyric:
        return LyricSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.audioSource:
        return AudioSourceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.about:
        return AboutSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.labFunctions:
        return LabFunctionsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.other:
        return OtherSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.none:
        return const SizedBox.shrink();
    }
  }

  /// 构建 Fluent UI 二级页面标题
  Widget _buildFluentHeader(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    
    String pageName = '';
    switch (_currentSubPage) {
      case SettingsSubPage.appearance: pageName = '外观'; break;
      case SettingsSubPage.thirdPartyAccounts: pageName = '第三方账号'; break;
      case SettingsSubPage.lyric: pageName = '歌词'; break;
      case SettingsSubPage.audioSource: pageName = '音源设置'; break;
      case SettingsSubPage.about: pageName = '关于'; break;
      case SettingsSubPage.labFunctions: pageName = '实验室功能'; break;
      case SettingsSubPage.other: pageName = '其它设置'; break;
      case SettingsSubPage.none: return const Text('设置');
    }

    return Row(
      children: [
        fluent_ui.Tooltip(
          message: '返回',
          child: fluent_ui.IconButton(
            icon: const Icon(fluent_ui.FluentIcons.back),
            onPressed: closeSubPage,
          ),
        ),
        const SizedBox(width: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: closeSubPage,
            child: Text(
              '设置',
              style: theme.typography.title?.copyWith(
                color: theme.resources.textFillColorSecondary,
                fontSize: 20,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            fluent_ui.FluentIcons.chevron_right,
            size: 12,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        Text(
          pageName,
          style: theme.typography.title?.copyWith(fontSize: 20),
        ),
      ],
    );
  }
}
