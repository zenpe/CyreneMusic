import '../services/structured_log_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../features/audio_source/audio_source_feature.dart';
import '../layouts/navidrome_main_layout.dart';
import '../layouts/main_layout.dart';
import '../services/persistent_storage_service.dart';
import '../services/playback/playback_service.dart';
import 'navidrome_setup_page.dart';
import 'mobile_setup_page.dart';

/// 移动端应用入口控制器
///
/// 根据登录、协议确认和音源配置状态决定显示引导页还是主布局。
/// 使用内部状态管理避免重建 Navigator。
class MobileAppGate extends StatefulWidget {
  const MobileAppGate({super.key});

  @override
  State<MobileAppGate> createState() => _MobileAppGateState();
}

class _MobileAppGateState extends State<MobileAppGate>
    with WidgetsBindingObserver {
  final AudioSourceFacade _audioSourceFacade = AudioSourceFacade();
  late bool _wasLoggedIn;
  late final Future<void> _authInitialization;

  Widget _buildHomeByRoute(AppGateRoute route) {
    return switch (route) {
      AppGateRoute.navidromeMain => const NavidromeMainLayout(),
      AppGateRoute.navidromeSetup => const NavidromeSetupPage(),
      AppGateRoute.regularMain => const MainLayout(),
      AppGateRoute.regularSetup => const MobileSetupPage(),
    };
  }

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = _audioSourceFacade.isLoggedIn;
    WidgetsBinding.instance.addObserver(this);
    _audioSourceFacade.addEntryStateListener(_onStateChanged);
    _authInitialization = _audioSourceFacade.ensureAuthInitialized();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioSourceFacade.removeEntryStateListener(_onStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      unawaited(_persistPlaybackSession());
    }
  }

  Future<void> _persistPlaybackSession() async {
    try {
      await PlaybackService().persistSessionImmediately();
      await PersistentStorageService().forceBackup();
    } catch (e) {
      StructuredLogService.log('⚠️ [MobileAppGate] 生命周期保存播放会话失败: $e');
    }
  }

  void _onStateChanged() {
    if (mounted) {
      final loggedIn = _audioSourceFacade.isLoggedIn;
      if (_wasLoggedIn && !loggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _audioSourceFacade.isLoggedIn) return;
          Navigator.of(
            context,
            rootNavigator: true,
          ).popUntil((route) => route.isFirst);
        });
      }
      _wasLoggedIn = loggedIn;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _authInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildHomeByRoute(_audioSourceFacade.resolveEntryRoute());
      },
    );
  }
}
