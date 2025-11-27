import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../utils/theme_manager.dart';
import '../services/url_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/layout_preference_service.dart';
import '../services/cache_service.dart';
import '../services/download_service.dart';
import '../services/audio_quality_service.dart';
import '../services/player_background_service.dart';
import 'settings_page/user_card.dart';
import 'settings_page/third_party_accounts.dart';
import 'settings_page/appearance_settings.dart';
import 'settings_page/lyric_settings.dart';
import 'settings_page/playback_settings.dart';
import 'settings_page/network_settings.dart';
import 'settings_page/storage_settings.dart';
import 'settings_page/about_settings.dart';
import 'settings_page/appearance_settings_page.dart';
import 'settings_page/third_party_accounts_page.dart';
import 'settings_page/lyric_settings_page.dart';

/// 设置页面子页面枚举
enum SettingsSubPage {
  none,
  appearance,
  thirdPartyAccounts,
  lyric,
}

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _rebuildScheduled = false;
  
  // 当前显示的子页面
  SettingsSubPage _currentSubPage = SettingsSubPage.none;

  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rebuildScheduled = false;
      setState(() {});
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
    AuthService().addListener(_onAuthChanged);
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
    final isLoggedIn = AuthService().isLoggedIn;
    print('⚙️ [SettingsPage] 当前登录状态: $isLoggedIn');
    
    if (isLoggedIn) {
      print('⚙️ [SettingsPage] 用户已登录，开始获取IP归属地...');
      LocationService().fetchLocation();
    } else {
      print('⚙️ [SettingsPage] 用户未登录，跳过获取IP归属地');
    }
  }

  @override
  void dispose() {
    ThemeManager().removeListener(_onThemeChanged);
    UrlService().removeListener(_onUrlServiceChanged);
    AuthService().removeListener(_onAuthChanged);
    LocationService().removeListener(_onLocationChanged);
    LayoutPreferenceService().removeListener(_onLayoutPreferenceChanged);
    CacheService().removeListener(_onCacheChanged);
    DownloadService().removeListener(_onDownloadChanged);
    AudioQualityService().removeListener(_onAudioQualityChanged);
    PlayerBackgroundService().removeListener(_onPlayerBackgroundChanged);
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
    if (AuthService().isLoggedIn) {
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
    setState(() {
      _currentSubPage = subPage;
    });
  }
  
  /// 关闭子页面，返回主设置页面
  void closeSubPage() {
    setState(() {
      _currentSubPage = SettingsSubPage.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否使用 Fluent UI
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// 构建 Material UI 版本
  Widget _buildMaterialUI(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          // 简单的左右滑动效果
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
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    // 用户卡片（需随登录状态刷新，不能使用 const）
                    UserCard(),
                    const SizedBox(height: 24),
                    
                    // 第三方账号管理（需随登录状态刷新，不能使用 const）
                    ThirdPartyAccounts(onTap: () => openSubPage(SettingsSubPage.thirdPartyAccounts)),
                    const SizedBox(height: 24),
                    
                    // 外观设置
                    AppearanceSettings(onTap: () => openSubPage(SettingsSubPage.appearance)),
                    const SizedBox(height: 24),
                    
                    // 歌词设置（仅 Windows 和 Android 平台显示）
                    LyricSettings(onTap: () => openSubPage(SettingsSubPage.lyric)),
                    const SizedBox(height: 24),
                    
                    // 播放设置
                    const PlaybackSettings(),
                    const SizedBox(height: 24),
                    
                    // 网络设置
                    const NetworkSettings(),
                    const SizedBox(height: 24),
                    
                    // 存储设置
                    const StorageSettings(),
                    const SizedBox(height: 24),
                    
                    // 关于
                    const AboutSettings(),
                    const SizedBox(height: 24),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
  
  /// 获取页面标题
  String _getPageTitle() {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return '外观设置';
      case SettingsSubPage.thirdPartyAccounts:
        return '第三方账号管理';
      case SettingsSubPage.lyric:
        return '歌词设置';
      case SettingsSubPage.none:
        return '设置';
    }
  }

  /// 构建 Material UI 子页面
  Widget _buildMaterialSubPage(BuildContext context, ColorScheme colorScheme) {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return AppearanceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.thirdPartyAccounts:
        return ThirdPartyAccountsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.lyric:
        return LyricSettingsContent(onBack: closeSubPage, embed: true);
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
          final offset = isMain
              ? const Offset(-1.0, 0.0) // 主页面从左侧进入/退出
              : const Offset(1.0, 0.0); // 子页面从右侧进入/退出
              
          return SlideTransition(
            position: Tween<Offset>(
              begin: offset,
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic, // 统一使用 easeInOutCubic
            )),
            child: child,
          );
        },
        child: _currentSubPage != SettingsSubPage.none
            ? KeyedSubtree(
                key: ValueKey('sub_settings_${_currentSubPage.name}'),
                child: _buildFluentSubPage(context),
              )
            : KeyedSubtree(
                key: const ValueKey('main_settings'),
                child: fluent_ui.ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    // 用户卡片
                    UserCard(),
                    const SizedBox(height: 16),
                    
                    // 第三方账号管理
                    ThirdPartyAccounts(onTap: () => openSubPage(SettingsSubPage.thirdPartyAccounts)),
                    const SizedBox(height: 16),
                    
                    // 外观设置
                    AppearanceSettings(onTap: () => openSubPage(SettingsSubPage.appearance)),
                    const SizedBox(height: 16),
                    
                    // 歌词设置
                    LyricSettings(onTap: () => openSubPage(SettingsSubPage.lyric)),
                    const SizedBox(height: 16),
                    
                    // 播放设置
                    const PlaybackSettings(),
                    const SizedBox(height: 16),
                    
                    // 网络设置
                    const NetworkSettings(),
                    const SizedBox(height: 16),
                    
                    // 存储设置
                    const StorageSettings(),
                    const SizedBox(height: 16),
                    
                    // 关于
                    const AboutSettings(),
                    const SizedBox(height: 16),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
  
  /// 构建 Fluent UI 头部（面包屑）
  Widget _buildFluentHeader(BuildContext context) {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return AppearanceSettingsContent(onBack: closeSubPage).buildFluentBreadcrumb(context);
      case SettingsSubPage.thirdPartyAccounts:
        return ThirdPartyAccountsContent(onBack: closeSubPage).buildFluentBreadcrumb(context);
      case SettingsSubPage.lyric:
        return LyricSettingsContent(onBack: closeSubPage).buildFluentBreadcrumb(context);
      case SettingsSubPage.none:
        return const Text('设置');
    }
  }
  
  /// 构建 Fluent UI 子页面
  Widget _buildFluentSubPage(BuildContext context) {
    switch (_currentSubPage) {
      case SettingsSubPage.appearance:
        return AppearanceSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.thirdPartyAccounts:
        return ThirdPartyAccountsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.lyric:
        return LyricSettingsContent(onBack: closeSubPage, embed: true);
      case SettingsSubPage.none:
        return const SizedBox.shrink();
    }
  }
}