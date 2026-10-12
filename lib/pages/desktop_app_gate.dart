import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/auth_overlay_service.dart';
import '../features/audio_source/audio_source_feature.dart';
import '../layouts/fluent_main_layout.dart';
import '../layouts/navidrome_main_layout.dart';
import '../pages/navidrome_setup_page.dart';
import 'desktop_setup_page.dart';

/// 桌面端应用入口控制器
///
/// 根据登录、协议确认和音源配置状态决定显示引导页还是主布局。
/// 使用内部状态管理避免重建 Navigator。
class DesktopAppGate extends StatefulWidget {
  const DesktopAppGate({super.key});

  @override
  State<DesktopAppGate> createState() => _DesktopAppGateState();
}

class _DesktopAppGateState extends State<DesktopAppGate> {
  final AudioSourceFacade _audioSourceFacade = AudioSourceFacade();
  late bool _wasLoggedIn;
  late final Future<void> _authInitialization;

  Widget _buildHomeByRoute(AppGateRoute route) {
    return switch (route) {
      AppGateRoute.navidromeMain => const NavidromeMainLayout(),
      AppGateRoute.navidromeSetup => const NavidromeSetupPage(),
      AppGateRoute.regularMain => const FluentMainLayout(),
      // Re-evaluate login and consent even when the setup route is unchanged.
      AppGateRoute.regularSetup => DesktopSetupPage(),
    };
  }

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = _audioSourceFacade.isLoggedIn;
    _audioSourceFacade.addEntryStateListener(_onStateChanged);
    _authInitialization = _audioSourceFacade.ensureAuthInitialized();
  }

  @override
  void dispose() {
    _audioSourceFacade.removeEntryStateListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      final loggedIn = _audioSourceFacade.isLoggedIn;
      if (_wasLoggedIn && !loggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _audioSourceFacade.isLoggedIn) return;
          AuthOverlayService().hide(false);
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
          return const Center(child: fluent.ProgressRing());
        }
        return _buildHomeByRoute(_audioSourceFacade.resolveEntryRoute());
      },
    );
  }
}
